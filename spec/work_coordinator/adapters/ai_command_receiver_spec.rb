# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Adapters::AiCommandReceiver do
  subject(:receiver) do
    described_class.new(
      inner: inner,
      ai_command_handler: ai_handler,
      deliver_to_main_session: ->(**) {},
      restart_coordinator: coordinator.restart,
      update_and_restart: coordinator.update
    )
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

  # Records calls to both coordinator use cases in one memoized helper.
  let(:coordinator) do
    Class.new do
      attr_reader :restart_calls, :update_calls

      def initialize
        @restart_calls = []
        @update_calls  = []
      end

      def restart = -> { @restart_calls << :called }
      def update = -> { @update_calls << :called }
    end.new
  end

  context "when the message has a work item ref prefix (e.g. MS-123)" do
    let(:msg) { { work_item_ref: "MS-123", body: "do it", received_at: Time.now } }
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

  describe "verb routing" do
    # Verb routing contexts share a recording deliver_to_main_session callable
    # and override subject to inject it.

    subject(:receiver) do
      described_class.new(
        inner: inner,
        ai_command_handler: ai_handler,
        deliver_to_main_session: deliver_to_main,
        restart_coordinator: coordinator.restart,
        update_and_restart: coordinator.update
      )
    end

    let(:deliveries) { [] }
    let(:deliver_to_main) do
      lambda do |workspace_name:, instructions:, recipient:|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient }
      end
    end

    # "ai: claude MS - add validation" is split by MessagesInboxPoller as:
    #   work_item_ref: "claude", body: "MS - add validation"
    context "with verb 'claude' (e.g. ai: claude MS - add validation)" do
      let(:messages) { [{ work_item_ref: "claude", body: "MS - add validation", received_at: Time.now }] }

      it "routes to deliver_to_main_session with correct args" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "add validation", recipient: nil }
        )
      end

      it "does not call the ai_command_handler" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to be_empty
      end

      it "does not yield to the outer block" do
        yielded = []
        receiver.start { |m| yielded << m }
        expect(yielded).to be_empty
      end
    end

    context "with verb 'main' (e.g. ai: main MS - refactor)" do
      let(:messages) { [{ work_item_ref: "main", body: "MS - refactor", received_at: Time.now }] }

      it "routes to deliver_to_main_session" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "refactor", recipient: nil }
        )
      end

      it "does not call the ai_command_handler" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to be_empty
      end
    end

    context "with verb 'new' (e.g. ai: new MS - split pane)" do
      let(:msg) { { work_item_ref: "new", body: "MS - split pane", received_at: Time.now } }
      let(:messages) { [msg] }

      it "routes to ai_command_handler, not deliver_to_main_session" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
        expect(deliveries).to be_empty
      end
    end

    context "with verb 'bash' (e.g. ai: bash MS - run tests)" do
      let(:msg) { { work_item_ref: "bash", body: "MS - run tests", received_at: Time.now } }
      let(:messages) { [msg] }

      it "routes to ai_command_handler, not deliver_to_main_session" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
        expect(deliveries).to be_empty
      end
    end

    # "ai: MS - do something" splits as work_item_ref: "MS", body: "- do something"
    # Reassembled: "MS - do something" → AiCommand has no verb, send_to_main_session? = false
    context "without a verb (e.g. ai: MS - do something)" do
      let(:msg) { { work_item_ref: "MS", body: "- do something", received_at: Time.now } }
      let(:messages) { [msg] }

      it "routes to ai_command_handler" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
        expect(deliveries).to be_empty
      end
    end

    # "ai: what is the status" splits as work_item_ref: "what", body: "is the status"
    context "with free-form text (e.g. ai: what is the status)" do
      let(:msg) { { work_item_ref: "what", body: "is the status", received_at: Time.now } }
      let(:messages) { [msg] }

      it "routes to ai_command_handler" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
        expect(deliveries).to be_empty
      end
    end
  end

  describe "slash command routing" do
    subject(:receiver) do
      described_class.new(
        inner: inner,
        ai_command_handler: ai_handler,
        deliver_to_main_session: deliver_to_main,
        restart_coordinator: coordinator.restart,
        update_and_restart: coordinator.update
      )
    end

    let(:deliveries) { [] }
    let(:deliver_to_main) do
      lambda do |workspace_name:, instructions:, recipient:|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient }
      end
    end

    # "ai: /build MS add OAuth support" splits as:
    #   work_item_ref: "/build", body: "MS add OAuth support"
    context "with /build MS add OAuth support" do
      let(:messages) { [{ work_item_ref: "/build", body: "MS add OAuth support", received_at: Time.now }] }

      it "routes to deliver_to_main_session with correct workspace and instructions" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "We're building a feature: add OAuth support", recipient: nil }
        )
      end

      it "does not call the ai_command_handler" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to be_empty
      end
    end

    # "ai: /clear MS" splits as: work_item_ref: "/clear", body: "MS"
    context "with /clear MS" do
      let(:messages) { [{ work_item_ref: "/clear", body: "MS", received_at: Time.now }] }

      it "routes to deliver_to_main_session with instructions '/clear'" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "/clear", recipient: nil }
        )
      end
    end

    # "ai: /stop MS" splits as: work_item_ref: "/stop", body: "MS"
    context "with /stop MS" do
      let(:messages) { [{ work_item_ref: "/stop", body: "MS", received_at: Time.now }] }

      it "routes to deliver_to_main_session with instructions 'C-c'" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "C-c", recipient: nil }
        )
      end
    end

    # "ai: /test MS" splits as: work_item_ref: "/test", body: "MS"
    context "with /test MS (no args)" do
      let(:messages) { [{ work_item_ref: "/test", body: "MS", received_at: Time.now }] }

      it "routes with 'Run the test suite'" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "Run the test suite", recipient: nil }
        )
      end
    end

    # "ai: /test MS user model" splits as: work_item_ref: "/test", body: "MS user model"
    context "with /test MS user model" do
      let(:messages) { [{ work_item_ref: "/test", body: "MS user model", received_at: Time.now }] }

      it "routes with 'Run tests: user model'" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "Run tests: user model", recipient: nil }
        )
      end
    end

    # "ai: /unknown MS foo" splits as: work_item_ref: "/unknown", body: "MS foo"
    # Unrecognized slash verb falls through to ai_command_handler.
    context "with /unknown MS foo (unrecognized slash verb)" do
      let(:msg) { { work_item_ref: "/unknown", body: "MS foo", received_at: Time.now } }
      let(:messages) { [msg] }

      it "falls through to ai_command_handler" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
        expect(deliveries).to be_empty
      end
    end
  end

  describe "slash_commands_enabled: false" do
    subject(:receiver) do
      described_class.new(
        inner: inner,
        ai_command_handler: ai_handler,
        deliver_to_main_session: deliver_to_main,
        restart_coordinator: coordinator.restart,
        update_and_restart: coordinator.update,
        slash_commands_enabled: false
      )
    end

    let(:deliveries) { [] }
    let(:deliver_to_main) do
      lambda do |workspace_name:, instructions:, recipient:|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient }
      end
    end

    # "ai: /build MS add OAuth" would normally be routed to deliver_to_main.
    # With slash_commands_enabled: false it should fall through to ai_command_handler.
    context "with a recognized slash command /build MS" do
      let(:msg) { { work_item_ref: "/build", body: "MS add OAuth", received_at: Time.now } }
      let(:messages) { [msg] }

      it "bypasses slash command routing and calls ai_command_handler instead" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
        expect(deliveries).to be_empty
      end
    end

    context "with a coordinator verb" do
      let(:msg) { { work_item_ref: "restart", body: nil, received_at: Time.now } }
      let(:messages) { [msg] }

      it "falls through to ai_command_handler" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
        expect(coordinator.restart_calls).to be_empty
      end
    end
  end

  describe "coordinator command routing" do
    subject(:receiver) do
      described_class.new(
        inner: inner,
        ai_command_handler: ai_handler,
        deliver_to_main_session: deliver_to_main,
        restart_coordinator: coordinator.restart,
        update_and_restart: coordinator.update
      )
    end

    let(:deliveries) { [] }
    let(:deliver_to_main) do
      lambda do |workspace_name:, instructions:, recipient:|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient }
      end
    end

    # "ai: /restart" splits as work_item_ref: "/restart", body: nil
    context "with /restart" do
      let(:messages) { [{ work_item_ref: "/restart", body: nil, received_at: Time.now }] }

      it "invokes the restart coordinator explicitly and never delivers to main" do
        receiver.start { |m| m }
        expect(coordinator.restart_calls).to eq([:called])
        expect(deliveries).to be_empty
        expect(ai_handler_calls).to be_empty
      end
    end

    # "ai: restart" splits as work_item_ref: "restart", body: nil
    context "with a bare 'restart' (ai: restart)" do
      let(:messages) { [{ work_item_ref: "restart", body: nil, received_at: Time.now }] }

      it "invokes the restart coordinator explicitly and never delivers to main" do
        receiver.start { |m| m }
        expect(coordinator.restart_calls).to eq([:called])
        expect(deliveries).to be_empty
      end
    end

    context "with /update" do
      let(:messages) { [{ work_item_ref: "/update", body: nil, received_at: Time.now }] }

      it "invokes update_and_restart" do
        receiver.start { |m| m }
        expect(coordinator.update_calls).to eq([:called])
        expect(deliveries).to be_empty
      end
    end

    context "with a bare 'update' (ai: update)" do
      let(:messages) { [{ work_item_ref: "update", body: nil, received_at: Time.now }] }

      it "invokes update_and_restart" do
        receiver.start { |m| m }
        expect(coordinator.update_calls).to eq([:called])
      end
    end

    context "with 'update the readme'" do
      let(:msg) { { work_item_ref: "update", body: "the readme", received_at: Time.now } }
      let(:messages) { [msg] }

      it "is not a coordinator command and falls through to ai_command_handler" do
        receiver.start { |m| m }
        expect(coordinator.update_calls).to be_empty
        expect(coordinator.restart_calls).to be_empty
        expect(ai_handler_calls).to eq([msg])
      end
    end

    context "with '/update the readme'" do
      let(:msg) { { work_item_ref: "/update", body: "the readme", received_at: Time.now } }
      let(:messages) { [msg] }

      it "is not a coordinator command and falls through to ai_command_handler" do
        receiver.start { |m| m }
        expect(coordinator.update_calls).to be_empty
        expect(deliveries).to be_empty
        expect(ai_handler_calls).to eq([msg])
      end
    end

    context "with '/restart MS'" do
      let(:msg) { { work_item_ref: "/restart", body: "MS", received_at: Time.now } }
      let(:messages) { [msg] }

      it "is not a coordinator command and falls through to ai_command_handler" do
        receiver.start { |m| m }
        expect(coordinator.restart_calls).to be_empty
        expect(deliveries).to be_empty
        expect(ai_handler_calls).to eq([msg])
      end
    end

    context "with 'restart the build'" do
      let(:msg) { { work_item_ref: "restart", body: "the build", received_at: Time.now } }
      let(:messages) { [msg] }

      it "is not a coordinator command and falls through to ai_command_handler" do
        receiver.start { |m| m }
        expect(coordinator.restart_calls).to be_empty
        expect(ai_handler_calls).to eq([msg])
      end
    end

    context "with a routable message (ABC-1 ...)" do
      let(:msg) { { work_item_ref: "ABC-1", body: "restart", received_at: Time.now } }
      let(:messages) { [msg] }

      it "is yielded to the block untouched" do
        yielded = []
        receiver.start { |m| yielded << m }
        expect(yielded).to eq([msg])
        expect(coordinator.restart_calls).to be_empty
      end
    end

    context "with a reply: message" do
      let(:msg) { { work_item_ref: "reply:", body: "update", received_at: Time.now } }
      let(:messages) { [msg] }

      it "is yielded to the block untouched" do
        yielded = []
        receiver.start { |m| yielded << m }
        expect(yielded).to eq([msg])
        expect(coordinator.update_calls).to be_empty
      end
    end
  end
end
