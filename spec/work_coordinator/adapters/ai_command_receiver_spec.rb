# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Adapters::AiCommandReceiver do
  subject(:receiver) do
    described_class.new(inner: inner, ai_command_handler: ai_handler)
  end

  let(:messages) { [] }
  let(:inner) do
    Class.new do
      include WorkCoordinator::Ports::MessageReceiver

      def initialize(messages)
        @messages = messages
        @stopped  = false
      end

      def start(&block)
        @messages.each { |msg| block.call(msg) }
      end

      def stop
        @stopped = true
      end

      def stopped?
        @stopped
      end
    end.new(messages)
  end

  let(:ai_handler_calls) { [] }
  let(:ai_handler) { ->(msg) { ai_handler_calls << msg } }

  context "when the message has a work item ref prefix (e.g. GE-123)" do
    let(:msg) { { work_item_ref: "GE-123", body: "do it", received_at: Time.now } }
    let(:messages) { [msg] }

    it "forwards to the block and does not call the ai_command_handler" do
      yielded = []
      receiver.start { |m| yielded << m }

      expect(yielded).to eq([msg])
      expect(ai_handler_calls).to be_empty
    end
  end

  context "when the message is a reply: prefix" do
    let(:msg) { { work_item_ref: "reply:", body: "investigate this", received_at: Time.now } }
    let(:messages) { [msg] }

    it "forwards to the block and does not call the ai_command_handler" do
      yielded = []
      receiver.start { |m| yielded << m }

      expect(yielded).to eq([msg])
      expect(ai_handler_calls).to be_empty
    end
  end

  context "when the message is freeform (no routable prefix)" do
    let(:msg) { { work_item_ref: "add", body: "error handling to the auth service", received_at: Time.now } }
    let(:messages) { [msg] }

    it "calls the ai_command_handler with the original message hash and does not yield to the block" do
      yielded = []
      receiver.start { |m| yielded << m }

      expect(yielded).to be_empty
      expect(ai_handler_calls).to eq([msg])
    end
  end

  describe "#stop" do
    it "delegates to the inner receiver" do
      receiver.stop

      expect(inner.stopped?).to be(true)
    end
  end
end
