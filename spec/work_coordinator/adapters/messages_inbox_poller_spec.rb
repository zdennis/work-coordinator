# frozen_string_literal: true

require "spec_helper"
require "work_coordinator/adapters/messages_inbox_poller"

RSpec.describe WorkCoordinator::Adapters::MessagesInboxPoller do
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
      described_class.new(inbound_message_repo: double("repo"))
    end

    def parse(text)
      row = { "text" => text, "date" => 0, "guid" => "abc" }
      poller.send(:parse_row, row)
    end

    context "with an ai: prefix message (e.g. 'ai: /build GE add OAuth')" do
      it "strips the ai: prefix before splitting" do
        result = parse("ai: /build GE add OAuth")
        expect(result[:work_item_ref]).to eq("/build")
        expect(result[:body]).to eq("GE add OAuth")
      end
    end

    context "with a bare slash command (e.g. '/build GE add OAuth')" do
      it "leaves the slash intact as work_item_ref" do
        result = parse("/build GE add OAuth")
        expect(result[:work_item_ref]).to eq("/build")
        expect(result[:body]).to eq("GE add OAuth")
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
