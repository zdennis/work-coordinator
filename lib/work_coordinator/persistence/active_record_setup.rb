require "active_record"
require "sqlite3"

module WorkCoordinator
  module Persistence
    def self.connect!(database: ENV.fetch("WC_DATABASE", "db/work_coordinator.sqlite3"))
      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: database
      )
      ActiveRecord::Base.logger = Logger.new($stdout) if ENV["WC_SQL_LOG"]
    end

    def self.migrate!
      ActiveRecord::MigrationContext.new("db/migrate").migrate
    end
  end
end
