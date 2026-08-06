# frozen_string_literal: true

module WorkCoordinator
  class Container
    attr_reader :work_item_repo, :event_store, :agent_session, :message_sender,
                :message_receiver, :route_message, :register_work_item,
                :start_work_item, :notify_human

    def initialize(db_path: ENV.fetch("WC_DATABASE", "db/work_coordinator.sqlite3"),
                   socket_path: ENV.fetch("WC_SOCKET", "/tmp/work-coordinator.sock"),
                   mode: :local) # rubocop:disable Lint/UnusedMethodArgument
      Persistence.connect!(database: db_path)
      Persistence.migrate!
      @work_item_repo   = Adapters::SqliteWorkItemRepository.new
      @event_store      = Adapters::SqliteEventStore.new
      @agent_session    = Adapters::TmuxAgentSession.new(work_item_repo: @work_item_repo)
      @message_sender   = Adapters::SocketMessageSender.new(socket_path: socket_path)
      @message_receiver = Adapters::SocketMessageReceiver.new(socket_path: socket_path)
      wire!
    end

    private

    def wire!
      @register_work_item = Application::RegisterWorkItem.new(work_item_repo: @work_item_repo,
                                                              event_store: @event_store)
      @start_work_item    = Application::StartWorkItem.new(work_item_repo: @work_item_repo,
                                                           agent_session: @agent_session, event_store: @event_store)
      @route_message      = Application::RouteMessage.new(work_item_repo: @work_item_repo,
                                                          agent_session: @agent_session, event_store: @event_store)
      @notify_human       = Application::NotifyHuman.new(message_sender: @message_sender,
                                                         work_item_repo: @work_item_repo, event_store: @event_store)
    end
  end
end
