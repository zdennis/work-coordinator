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

      MAC_EPOCH_OFFSET_SECONDS = 978_307_200
      LOOKBACK_DEFAULT = 24 * 3600

      def initialize(
        inbound_message_repo:,
        db_path: File.expand_path("~/Library/Messages/chat.db"),
        poll_interval: 5
      )
        @inbound_message_repo = inbound_message_repo
        @db_path = db_path
        @poll_interval = poll_interval
        @running = false
      end

      def start(lookback: LOOKBACK_DEFAULT, &block)
        @running = true
        check_guid_column!
        @last_date = ((Time.now.to_f - MAC_EPOCH_OFFSET_SECONDS - lookback) * 1_000_000_000).to_i

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
        SELECT rowid, text, date, guid FROM message
        WHERE is_from_me = 0 AND text LIKE 'ai: %' AND date > ?
        ORDER BY date ASC
      SQL

      private

      def check_guid_column!
        columns = with_db { |db| db.execute("PRAGMA table_info(message)").map { _1["name"] } }
        return if columns.include?("guid")

        raise "chat.db has no 'guid' column — requires macOS 10.15+"
      end

      def poll_once(&)
        with_db do |db|
          rows = db.execute(INBOX_SQL, @last_date)
          rows.each do |row|
            message = parse_row(row)
            next if @inbound_message_repo.seen?(message[:guid])

            yield message
            @inbound_message_repo.record(message[:guid])
          end
          @last_date = rows.map { _1["date"] }.max if rows.any?
        end
      end

      def parse_row(row)
        parts = row["text"][4..].split(" ", 2)
        {
          guid: row["guid"],
          work_item_ref: parts[0],
          body: parts[1].to_s.strip,
          received_at: mac_time_to_time(row["date"])
        }
      end

      def mac_time_to_time(mac_nanoseconds)
        Time.at(MAC_EPOCH_OFFSET_SECONDS + (mac_nanoseconds / 1_000_000_000.0))
      end

      def with_db
        tmp = File.join(Dir.tmpdir, "wc_chat_#{Process.pid}.db")
        FileUtils.cp(@db_path, tmp)
        db = SQLite3::Database.new(tmp)
        db.results_as_hash = true
        yield db
      ensure
        db&.close
        File.delete(tmp) if tmp && File.exist?(tmp)
      end
    end
  end
end
