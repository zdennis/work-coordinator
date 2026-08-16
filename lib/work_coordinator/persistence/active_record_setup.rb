# frozen_string_literal: true

require "active_record"
require "sqlite3"

module WorkCoordinator
  # ActiveRecord wiring for the coordinator's SQLite database.
  module Persistence
    # Establishes the connection, enabling SQL logging to stdout when
    # `WC_SQL_LOG` is set.
    #
    # @param database [String] path to the SQLite file
    # @return [void]
    def self.connect!(database: ENV.fetch("WC_DATABASE", "db/work_coordinator.sqlite3"))
      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: database
      )
      ActiveRecord::Base.logger = Logger.new($stdout) if ENV["WC_SQL_LOG"]
    end

    # Runs any pending migrations from `db/migrate`, relative to the working
    # directory.
    #
    # @return [void]
    def self.migrate!
      ActiveRecord::MigrationContext.new("db/migrate").migrate
    end
  end
end

require_relative "models/project_record"
require_relative "models/work_item_record"
require_relative "models/event_record"
require_relative "models/resource_lease_record"
require_relative "models/inbound_message_record"
require_relative "models/restart_state_record"
require_relative "models/workspace_agent_registration_record"
