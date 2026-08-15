# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "work_coordinator/adapters/messages_inbox_poller"

RSpec.describe WorkCoordinator::Adapters::MessagesInboxPoller do
  describe "#poll_once" do
    let(:repo) { WorkCoordinator::Adapters::InMemoryInboundMessageRepository.new }
    let(:db_path) { File.join(Dir.mktmpdir, "chat.db") }
    let(:poller) { described_class.new(inbound_message_repo: repo, db_path: db_path) }

    before do
      db = SQLite3::Database.new(db_path)
      db.execute(
        "CREATE TABLE message " \
        "(rowid INTEGER PRIMARY KEY, text TEXT, date INTEGER, guid TEXT, is_from_me INTEGER)"
      )
      db.execute("INSERT INTO message (text, date, guid, is_from_me) VALUES (?, ?, ?, ?)",
                 ["/restart", 1_000, "guid-1", 0])
      db.close
      poller.instance_variable_set(:@last_date, 0)
    end

    it "records the guid even when the block raises" do
      expect { poller.send(:poll_once) { raise "boom" } }.to raise_error("boom")
      expect(repo.recorded).to eq(["guid-1"])
    end

    it "records the guid even when the block never returns normally" do
      catch(:exec_replaced) do
        poller.send(:poll_once) { throw :exec_replaced }
      end
      expect(repo.recorded).to eq(["guid-1"])
    end

    it "never yields an already-seen guid" do
      seen_repo = WorkCoordinator::Adapters::InMemoryInboundMessageRepository.new(seen: ["guid-1"])
      seen_poller = described_class.new(inbound_message_repo: seen_repo, db_path: db_path)
      seen_poller.instance_variable_set(:@last_date, 0)

      yielded = []
      seen_poller.send(:poll_once) { |message| yielded << message }

      expect(yielded).to be_empty
    end

    it "yields an unseen guid exactly once across repeated polls" do
      yielded = []
      2.times { poller.send(:poll_once) { |message| yielded << message } }

      expect(yielded.map { _1[:guid] }).to eq(["guid-1"])
    end
  end

  describe "INBOX_SQL" do
    it "matches messages with the ai: prefix" do
      expect(described_class::INBOX_SQL).to include("text LIKE 'ai: %'")
    end

    it "also matches bare slash commands without the ai: prefix" do
      expect(described_class::INBOX_SQL).to include("text LIKE '/%'")
    end
  end

  describe "#parse_row (via private interface)" do
    let(:poller) do
      described_class.new(inbound_message_repo: instance_double(WorkCoordinator::Adapters::SqliteInboundMessageRepository))
    end

    def parse(text)
      row = { "text" => text, "date" => 0, "guid" => "abc" }
      poller.send(:parse_row, row)
    end

    context "with an ai: prefix message (e.g. 'ai: /build MS add OAuth')" do
      it "strips the ai: prefix before splitting" do
        result = parse("ai: /build MS add OAuth")
        expect(result[:work_item_ref]).to eq("/build")
        expect(result[:body]).to eq("MS add OAuth")
      end
    end

    context "with a bare slash command (e.g. '/build MS add OAuth')" do
      it "leaves the slash intact as work_item_ref" do
        result = parse("/build MS add OAuth")
        expect(result[:work_item_ref]).to eq("/build")
        expect(result[:body]).to eq("MS add OAuth")
      end
    end

    context "with a bare slash command and no args (e.g. '/help')" do
      it "sets work_item_ref to /help with an empty body" do
        result = parse("/help")
        expect(result[:work_item_ref]).to eq("/help")
        expect(result[:body]).to eq("")
      end
    end

    context "with a standard ai: routable message (e.g. 'ai: MS-123 do it')" do
      it "strips the ai: prefix and sets ref and body correctly" do
        result = parse("ai: MS-123 do it")
        expect(result[:work_item_ref]).to eq("MS-123")
        expect(result[:body]).to eq("do it")
      end
    end
  end
end
