# frozen_string_literal: true

require "fileutils"
require "sqlite3"
require "tmpdir"
require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    # Polls ~/Library/Messages/chat.db for inbound messages prefixed with 'ai: '.
    # Requires Full Disk Access (FDA) to be granted to the running process.
    class MessagesInboxPoller
      include Ports::MessageReceiver

      def initialize(
        db_path: File.expand_path("~/Library/Messages/chat.db"),
        poll_interval: 5
      )
        @db_path = db_path
        @poll_interval = poll_interval
        @running = false
      end

      def start(&block)
        @running = true
        @last_date = current_max_date

        loop do
          break unless @running

          poll_once(&block)
          sleep @poll_interval
        end
      end

      def stop
        @running = false
      end

      INBOX_SQL = <<~SQL
        SELECT rowid, text, date FROM message
        WHERE is_from_me = 0 AND text LIKE 'ai: %' AND date > ?
        ORDER BY date ASC
      SQL

      private

      def poll_once(&)
        with_db do |db|
          rows = db.execute(INBOX_SQL, @last_date)
          rows.each { |row| yield parse_row(row) }
          @last_date = rows.map { _1[2] }.max if rows.any?
        end
      end

      def parse_row(row)
        _rowid, text, _date = row
        parts = text[4..].split(" ", 2)
        { work_item_ref: parts[0], body: parts[1].to_s.strip, received_at: Time.now }
      end

      def with_db
        tmp = File.join(Dir.tmpdir, "wc_chat_#{Process.pid}.db")
        FileUtils.cp(@db_path, tmp)
        db = SQLite3::Database.new(tmp)
        yield db
      ensure
        db&.close
        File.delete(tmp) if tmp && File.exist?(tmp)
      end

      def current_max_date
        with_db { |db| db.execute("SELECT max(date) FROM message")&.dig(0, 0) || 0 }
      end
    end
  end
end
