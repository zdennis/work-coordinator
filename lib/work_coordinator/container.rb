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
    #   @return [Adapters::TmuxAgentSession]
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
    # @!attribute [r] ai_command_runner
    #   @return [Adapters::ClaudeWorkspaceCommandRunner]
    # @!attribute [r] dispatch_ai_command
    #   @return [Application::DispatchAiCommand]
    attr_reader :work_item_repo, :event_store, :agent_session, :message_sender,
                :message_receiver, :inbound_message_repo, :route_message,
                :register_work_item, :start_work_item, :notify_human,
                :ai_command_runner, :dispatch_ai_command

    # A receiver is built per mode and run concurrently; the sender is chosen
    # from the modes, with `:messages` winning over `:local` when both are given.
    #
    # @param db_path [String] SQLite file to connect to and migrate
    # @param socket_path [String] Unix socket used by `:local` mode
    # @param modes [Array<Symbol>, Symbol] any of `:local`, `:messages`
    # @raise [ArgumentError] when a mode is unrecognized
    def initialize(db_path: ENV.fetch("WC_DATABASE", "db/work_coordinator.sqlite3"),
                   socket_path: ENV.fetch("WC_SOCKET", "/tmp/work-coordinator.sock"),
                   modes: [:local])
      modes = Array(modes).map(&:to_sym).uniq
      @socket_path = socket_path
      Persistence.connect!(database: db_path)
      Persistence.migrate!
      @work_item_repo   = Adapters::SqliteWorkItemRepository.new
      @event_store      = Adapters::SqliteEventStore.new
      @agent_session    = Adapters::TmuxAgentSession.new(work_item_repo: @work_item_repo)
      @message_sender   = build_sender(modes)
      wire!
      @message_receiver = Adapters::CompositeMessageReceiver.new(build_receivers(modes))
    end

    private

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
      Adapters::AiCommandReceiver.new(inner: poller, ai_command_handler: method(:handle_ai_command))
    end

    def handle_ai_command(msg)
      body = "#{msg[:work_item_ref]} #{msg[:body]}".strip
      puts "AI command: #{body}"
      result = @dispatch_ai_command.call(body: body)
      if result.dispatched
        puts "AI command dispatched to '#{result.project}': #{result.summary}"
      else
        puts "AI command unmatched (#{result.failure_reason}): #{body}"
      end
    rescue StandardError => e
      warn "Error dispatching AI command: #{e.message}"
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
                                                              event_store: @event_store)
      @start_work_item    = Application::StartWorkItem.new(work_item_repo: @work_item_repo,
                                                           agent_session: @agent_session, event_store: @event_store)
      @route_message      = Application::RouteMessage.new(work_item_repo: @work_item_repo,
                                                          agent_session: @agent_session, event_store: @event_store)
      @notify_human       = Application::NotifyHuman.new(message_sender: @message_sender,
                                                         work_item_repo: @work_item_repo, event_store: @event_store)
      config = Config.new
      @ai_command_runner   = Adapters::ClaudeWorkspaceCommandRunner.new
      @dispatch_ai_command = Application::DispatchAiCommand.new(
        ai_command_runner: @ai_command_runner,
        message_sender: @message_sender,
        aliases: config.aliases
      )
    end
  end
end
