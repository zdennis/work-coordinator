# frozen_string_literal: true

module WorkCoordinator
  # Composition root: connects the database, picks adapters for the requested
  # modes, and wires up the application use cases. Constructing a container has
  # side effects — it opens the database and runs pending migrations.
  class Container
    # @!attribute [r] work_item_repo
    #   @return [Adapters::SqliteWorkItemRepository]
    # @!attribute [r] event_store
    #   @return [Adapters::SqliteEventStore]
    # @!attribute [r] agent_session
    #   @return [Adapters::WorkspaceAgentSession]
    # @!attribute [r] message_sender
    #   @return [Ports::MessageSender]
    # @!attribute [r] message_receiver
    #   @return [Adapters::CompositeMessageReceiver]
    # @!attribute [r] inbound_message_repo
    #   @return [Adapters::SqliteInboundMessageRepository, nil] only built in :messages mode
    # @!attribute [r] route_message
    #   @return [Application::RouteMessage]
    # @!attribute [r] register_work_item
    #   @return [Application::RegisterWorkItem]
    # @!attribute [r] start_work_item
    #   @return [Application::StartWorkItem]
    # @!attribute [r] notify_human
    #   @return [Application::NotifyHuman]
    # @!attribute [r] complete_work_item
    #   @return [Application::CompleteWorkItem]
    # @!attribute [r] ai_command_runner
    #   @return [Adapters::ClaudeWorkspaceCommandRunner]
    # @!attribute [r] dispatch_ai_command
    #   @return [Application::DispatchAiCommand]
    # @!attribute [r] handle_query
    #   @return [Application::HandleQuery]
    # @!attribute [r] deliver_to_main_session
    #   @return [Application::DeliverToMainSession]
    # @!attribute [r] project_repo
    #   @return [Adapters::SqliteProjectRepository]
    # @!attribute [r] project_resolver
    #   @return [Application::ProjectResolver]
    # @!attribute [r] set_default_project
    #   @return [Application::SetDefaultProject]
    # @!attribute [r] restart_state_repo
    #   @return [Adapters::SqliteRestartStateRepository]
    # @!attribute [r] git_runner
    #   @return [Adapters::ShellGitRunner]
    # @!attribute [r] restart_coordinator
    #   @return [Application::RestartCoordinator]
    # @!attribute [r] update_and_restart
    #   @return [Application::UpdateAndRestart]
    # @!attribute [r] workspace_agent_registry
    #   @return [Adapters::SqliteWorkspaceAgentRegistry]
    attr_reader :work_item_repo, :event_store, :agent_session, :message_sender,
                :message_receiver, :inbound_message_repo, :route_message,
                :register_work_item, :start_work_item, :notify_human,
                :ai_command_runner, :dispatch_ai_command, :handle_query,
                :deliver_to_main_session, :project_repo, :project_resolver,
                :set_default_project, :restart_state_repo, :git_runner,
                :restart_coordinator, :update_and_restart, :register_command_work_item,
                :workspace_agent_registry, :complete_work_item

    # A receiver is built per mode and run concurrently; the sender is chosen
    # from the modes, with `:messages` winning over `:local` when both are given.
    #
    # @param db_path [String] SQLite file to connect to and migrate
    # @param socket_path [String] Unix socket used by `:local` mode
    # @param modes [Array<Symbol>, Symbol] any of `:local`, `:messages`
    # @param argv [Array<String>] command line to re-exec on restart
    # @param env [Hash{String=>String}] environment to re-exec with
    # @raise [ArgumentError] when a mode is unrecognized
    def initialize(db_path: ENV.fetch("WC_DATABASE", "db/work_coordinator.sqlite3"),
                   socket_path: ENV.fetch("WC_SOCKET", "/tmp/work-coordinator.sock"),
                   modes: [:local],
                   argv: [$PROGRAM_NAME],
                   env: ENV.to_h)
      modes = Array(modes).map(&:to_sym).uniq
      @socket_path = socket_path
      @argv = argv
      @env = env
      Persistence.connect!(database: db_path)
      Persistence.migrate!
      build_core_adapters!(modes)
      wire!
      @message_receiver = Adapters::CompositeMessageReceiver.new(build_receivers(modes))
    end

    private

    def build_core_adapters!(modes)
      @project_repo     = Adapters::SqliteProjectRepository.new
      @project_resolver = Application::ProjectResolver.new(project_repo: @project_repo)
      @work_item_repo   = Adapters::SqliteWorkItemRepository.new
      @event_store      = Adapters::SqliteEventStore.new
      @workspace_agent_registry = Adapters::SqliteWorkspaceAgentRegistry.new
      tmux = Adapters::TmuxAgentSession.new(work_item_repo: @work_item_repo)
      @agent_session  = Adapters::WorkspaceAgentSession.new(tmux: tmux, registry: @workspace_agent_registry)
      @message_sender = build_sender(modes)
    end

    def build_receivers(modes)
      modes.map { |mode| build_receiver(mode) }
    end

    def build_receiver(mode)
      case mode
      when :local
        Adapters::SocketMessageReceiver.new(socket_path: @socket_path)
      when :messages
        build_messages_receiver
      else
        raise ArgumentError, "unknown mode: #{mode}"
      end
    end

    def build_messages_receiver
      @inbound_message_repo ||= Adapters::SqliteInboundMessageRepository.new
      poller = Adapters::MessagesInboxPoller.new(inbound_message_repo: @inbound_message_repo)
      Adapters::AiCommandReceiver.new(
        inner: poller,
        ai_command_handler: @ai_command_handler,
        deliver_to_main_session: @deliver_to_main_session,
        register_command_work_item: @register_command_work_item,
        restart_coordinator: @restart_coordinator,
        update_and_restart: @update_and_restart,
        slash_commands_enabled: Config.new.slash_commands_enabled?
      )
    end

    def build_sender(modes)
      if modes.include?(:messages)
        Adapters::AppleScriptMessageSender.new
      else
        Adapters::SocketMessageSender.new(socket_path: @socket_path)
      end
    end

    def wire!
      @register_work_item = Application::RegisterWorkItem.new(work_item_repo: @work_item_repo,
                                                              event_store: @event_store,
                                                              project_repo: @project_repo)
      @register_command_work_item = Application::RegisterCommandWorkItem.new(
        register_work_item: @register_work_item, work_item_repo: @work_item_repo
      )
      @start_work_item    = Application::StartWorkItem.new(work_item_repo: @work_item_repo,
                                                           agent_session: @agent_session, event_store: @event_store)
      @route_message      = Application::RouteMessage.new(work_item_repo: @work_item_repo,
                                                          agent_session: @agent_session, event_store: @event_store)
      human_deps = { message_sender: @message_sender, work_item_repo: @work_item_repo, event_store: @event_store }
      @notify_human       = Application::NotifyHuman.new(**human_deps)
      @complete_work_item = Application::CompleteWorkItem.new(**human_deps)
      wire_ai_commands!
      wire_restart!
    end

    def wire_restart!
      @restart_state_repo  = Adapters::SqliteRestartStateRepository.new
      @git_runner          = Adapters::ShellGitRunner.new(dir: coordinator_root)
      @restart_coordinator = Application::RestartCoordinator.new(
        message_sender: @message_sender,
        restart_state_repo: @restart_state_repo,
        argv: @argv,
        env: @env,
        before_exec: -> { ActiveRecord::Base.connection_pool.disconnect! }
      )
      @update_and_restart = Application::UpdateAndRestart.new(
        message_sender: @message_sender,
        restart_coordinator: @restart_coordinator,
        git_runner: @git_runner
      )
    end

    def coordinator_root = File.expand_path("../..", __dir__)

    def wire_ai_commands!
      config = Config.new
      @ai_command_runner   = Adapters::ClaudeWorkspaceCommandRunner.new
      @set_default_project = Application::SetDefaultProject.new(
        project_repo: @project_repo,
        project_resolver: @project_resolver
      )
      @dispatch_ai_command = build_dispatch_ai_command(config)
      @handle_query        = build_handle_query(config)
      @ai_command_handler  = Adapters::ConsoleAiCommandHandler.new(
        handle_query: @handle_query,
        dispatch_ai_command: @dispatch_ai_command,
        message_sender: @message_sender
      )
      wire_delivery!(config)
    end

    def build_dispatch_ai_command(config)
      Application::DispatchAiCommand.new(
        ai_command_runner: @ai_command_runner,
        message_sender: @message_sender,
        aliases: config.aliases,
        instruction_context: config.instruction_context,
        auto_launch_workspace: config.auto_launch_workspace,
        workspace_launch_timeout_seconds: config.workspace_launch_timeout_seconds,
        project_resolver: @project_resolver
      )
    end

    def build_handle_query(config)
      Application::HandleQuery.new(
        work_item_repo: @work_item_repo,
        event_store: @event_store,
        agent_session: @agent_session,
        config: config,
        message_sender: @message_sender,
        project_repo: @project_repo,
        project_resolver: @project_resolver,
        set_default_project: @set_default_project
      )
    end

    def wire_delivery!(config)
      @deliver_to_main_session = Application::DeliverToMainSession.new(
        agent_session: @agent_session,
        message_sender: @message_sender,
        aliases: config.aliases,
        instruction_context: config.instruction_context,
        project_repo: @project_repo
      )
    end
  end
end
