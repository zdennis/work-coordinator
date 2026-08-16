# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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
      lambda do |workspace_name:, instructions:, recipient:, work_item_ref: nil|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient,
                        work_item_ref: work_item_ref }
      end
    end

    # "ai: claude MS - add validation" is split by MessagesInboxPoller as:
    #   work_item_ref: "claude", body: "MS - add validation"
    context "with verb 'claude' (e.g. ai: claude MS - add validation)" do
      let(:messages) { [{ work_item_ref: "claude", body: "MS - add validation", received_at: Time.now }] }

      it "routes to deliver_to_main_session with correct args" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "add validation", recipient: nil, work_item_ref: nil }
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
          { workspace_name: "MS", instructions: "refactor", recipient: nil, work_item_ref: nil }
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

  describe "role token parsing" do
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
      lambda do |workspace_name:, instructions:, recipient:, work_item_ref: nil|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient,
                        work_item_ref: work_item_ref }
      end
    end

    # "ai:home: claude MS - add validation" is stripped by MessagesInboxPoller to
    # "home: claude MS - add validation", then split as:
    #   work_item_ref: "home:", body: "claude MS - add validation"
    context "with 'ai:home: claude MS - add validation'" do
      let(:messages) { [{ work_item_ref: "home:", body: "claude MS - add validation", received_at: Time.now }] }

      it "strips the role and still routes the verb to deliver_to_main_session" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "add validation", recipient: nil, work_item_ref: nil }
        )
      end
    end

    # "ai:h: MS - add validation" → work_item_ref: "h:", body: "MS - add validation"
    context "with 'ai:h: MS - add validation'" do
      let(:messages) { [{ work_item_ref: "h:", body: "MS - add validation", received_at: Time.now }] }

      it "hands the handler the role and a body with the token removed" do
        receiver.start { |m| m }
        expect(ai_handler_calls.first).to include(role: "h", work_item_ref: "MS", body: "- add validation")
        expect(deliveries).to be_empty
      end
    end

    # "ai:work: new MS - add validation" → work_item_ref: "work:", body: "new MS - add validation"
    context "with 'ai:work: new MS - add validation'" do
      let(:messages) { [{ work_item_ref: "work:", body: "new MS - add validation", received_at: Time.now }] }

      it "keeps the 'new' verb on the handler path with the role recorded" do
        receiver.start { |m| m }
        expect(ai_handler_calls.first).to include(role: "work", work_item_ref: "new", body: "MS - add validation")
        expect(deliveries).to be_empty
      end
    end

    context "with a role in front of a slash command ('ai:home: /clear MS')" do
      let(:messages) { [{ work_item_ref: "home:", body: "/clear MS", received_at: Time.now }] }

      it "dispatches the slash command with the role stripped" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "/clear", recipient: nil, work_item_ref: nil }
        )
      end
    end

    context "without a role ('ai: MS - add validation')" do
      let(:msg) { { work_item_ref: "MS", body: "- add validation", received_at: Time.now } }
      let(:messages) { [msg] }

      it "passes the message through untouched, with no role key added" do
        receiver.start { |m| m }
        expect(ai_handler_calls).to eq([msg])
      end
    end

    # "ai:home:WC fix the bug" — workspace embedded in the role token routes directly
    # to the named workspace. A work item is registered and its ref forwarded.
    context "with 'ai:home:WC fix the bug' (workspace embedded in role token)" do
      subject(:receiver) do
        described_class.new(
          inner: inner,
          ai_command_handler: ai_handler,
          deliver_to_main_session: deliver_to_main,
          register_command_work_item: register_command_work_item,
          restart_coordinator: coordinator.restart,
          update_and_restart: coordinator.update
        )
      end

      let(:messages) { [{ work_item_ref: "home:WC", body: "fix the bug", received_at: Time.now }] }

      let(:work_item_repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
      let(:event_store)    { WorkCoordinator::Application::InMemoryEventStore.new }
      let(:register_command_work_item) do
        WorkCoordinator::Application::RegisterCommandWorkItem.new(
          register_work_item: WorkCoordinator::Application::RegisterWorkItem.new(
            work_item_repo: work_item_repo, event_store: event_store
          ),
          work_item_repo: work_item_repo
        )
      end

      it "routes to deliver_to_main_session with the workspace and instructions" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          hash_including(workspace_name: "WC", instructions: "fix the bug")
        )
      end

      it "registers a work item and includes its ref in the delivery" do
        receiver.start { |m| m }
        expect(deliveries.first[:work_item_ref]).to eq("WC-1")
      end

      it "persists the work item with the correct workspace" do
        receiver.start { |m| m }
        expect(work_item_repo.find_all.first).to have_attributes(
          workspace_name: "WC",
          external_reference: "WC-1"
        )
      end
    end
  end

  describe "role gate" do
    subject(:receiver) do
      described_class.new(
        inner: inner,
        ai_command_handler: ai_handler,
        deliver_to_main_session: ->(**) {},
        restart_coordinator: coordinator.restart,
        update_and_restart: coordinator.update,
        config: config
      )
    end

    let(:tmpdir) { Dir.mktmpdir }
    let(:config_path) { File.join(tmpdir, "config.yml") }
    let(:config) { WorkCoordinator::Config.new(config_path) }

    after { FileUtils.remove_entry(tmpdir) }

    context "with role: home and role_aliases: [h]" do
      before { File.write(config_path, "role: home\nrole_aliases:\n  - h\n") }

      it "drops a message with no role token" do
        messages << { work_item_ref: "MS", body: "- add validation", received_at: Time.now }
        yielded = []
        receiver.start { |m| yielded << m }

        expect(ai_handler_calls).to be_empty
        expect(yielded).to be_empty
      end

      it "drops a message addressed to another role" do
        messages << { work_item_ref: "work:", body: "MS - add validation", received_at: Time.now }
        yielded = []
        receiver.start { |m| yielded << m }

        expect(ai_handler_calls).to be_empty
        expect(yielded).to be_empty
      end

      it "accepts a message addressed to its role" do
        messages << { work_item_ref: "home:", body: "MS - add validation", received_at: Time.now }
        receiver.start { |m| m }

        expect(ai_handler_calls.first).to include(role: "home", work_item_ref: "MS")
      end

      it "accepts a message addressed to one of its aliases" do
        messages << { work_item_ref: "h:", body: "MS - add validation", received_at: Time.now }
        receiver.start { |m| m }

        expect(ai_handler_calls.first).to include(role: "h", work_item_ref: "MS")
      end
    end

    context "with role: default" do
      before { File.write(config_path, "role: default\n") }

      it "accepts a message with no role token" do
        msg = { work_item_ref: "MS", body: "- add validation", received_at: Time.now }
        messages << msg
        receiver.start { |m| m }

        expect(ai_handler_calls).to eq([msg])
      end

      it "drops a message addressed to another role" do
        messages << { work_item_ref: "home:", body: "MS - add validation", received_at: Time.now }
        yielded = []
        receiver.start { |m| yielded << m }

        expect(ai_handler_calls).to be_empty
        expect(yielded).to be_empty
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
      lambda do |workspace_name:, instructions:, recipient:, work_item_ref: nil|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient,
                        work_item_ref: work_item_ref }
      end
    end

    # "ai: /build MS add OAuth support" splits as:
    #   work_item_ref: "/build", body: "MS add OAuth support"
    context "with /build MS add OAuth support" do
      let(:messages) { [{ work_item_ref: "/build", body: "MS add OAuth support", received_at: Time.now }] }

      it "routes to deliver_to_main_session with correct workspace and instructions" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "We're building a feature: add OAuth support", recipient: nil,
            work_item_ref: nil }
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
          { workspace_name: "MS", instructions: "/clear", recipient: nil, work_item_ref: nil }
        )
      end
    end

    # "ai: /stop MS" splits as: work_item_ref: "/stop", body: "MS"
    context "with /stop MS" do
      let(:messages) { [{ work_item_ref: "/stop", body: "MS", received_at: Time.now }] }

      it "routes to deliver_to_main_session with instructions 'C-c'" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "C-c", recipient: nil, work_item_ref: nil }
        )
      end
    end

    # "ai: /test MS" splits as: work_item_ref: "/test", body: "MS"
    context "with /test MS (no args)" do
      let(:messages) { [{ work_item_ref: "/test", body: "MS", received_at: Time.now }] }

      it "routes with 'Run the test suite'" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "Run the test suite", recipient: nil, work_item_ref: nil }
        )
      end
    end

    # "ai: /test MS user model" splits as: work_item_ref: "/test", body: "MS user model"
    context "with /test MS user model" do
      let(:messages) { [{ work_item_ref: "/test", body: "MS user model", received_at: Time.now }] }

      it "routes with 'Run tests: user model'" do
        receiver.start { |m| m }
        expect(deliveries).to contain_exactly(
          { workspace_name: "MS", instructions: "Run tests: user model", recipient: nil, work_item_ref: nil }
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
      lambda do |workspace_name:, instructions:, recipient:, work_item_ref: nil|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient,
                        work_item_ref: work_item_ref }
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
      lambda do |workspace_name:, instructions:, recipient:, work_item_ref: nil|
        deliveries << { workspace_name: workspace_name, instructions: instructions, recipient: recipient,
                        work_item_ref: work_item_ref }
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

  describe "work-items status" do
    subject(:receiver) do
      described_class.new(
        inner: inner,
        ai_command_handler: ai_handler,
        deliver_to_main_session: ->(**) {},
        restart_coordinator: coordinator.restart,
        update_and_restart: coordinator.update,
        work_items_status_fn: ->(msg:) { status_calls << msg }
      )
    end

    let(:status_calls) { [] }

    # "ai: work-items status" splits as work_item_ref: "work-items", body: "status"
    context "with a bare 'work-items status'" do
      let(:msg) { { work_item_ref: "work-items", body: "status", received_at: Time.now } }
      let(:messages) { [msg] }

      it "invokes the status function with the inbound message" do
        receiver.start { |m| m }
        expect(status_calls).to eq([msg])
        expect(ai_handler_calls).to be_empty
      end
    end

    context "with '/work-items status'" do
      let(:msg) { { work_item_ref: "/work-items", body: "status", received_at: Time.now } }
      let(:messages) { [msg] }

      it "invokes the status function" do
        receiver.start { |m| m }
        expect(status_calls).to eq([msg])
      end
    end

    context "with a bare 'work-items'" do
      let(:msg) { { work_item_ref: "work-items", body: nil, received_at: Time.now } }
      let(:messages) { [msg] }

      it "defaults to status" do
        receiver.start { |m| m }
        expect(status_calls).to eq([msg])
      end
    end

    context "with an unknown subcommand" do
      let(:msg) { { work_item_ref: "work-items", body: "explode", received_at: Time.now } }
      let(:messages) { [msg] }

      it "does nothing rather than guessing" do
        receiver.start { |m| m }
        expect(status_calls).to be_empty
        expect(ai_handler_calls).to be_empty
      end
    end

    # "ai:home:work-items status" — role token with coordinator verb in workspace slot
    context "with 'home:work-items status' (role-embedded coordinator verb)" do
      subject(:receiver) do
        described_class.new(
          inner: inner,
          ai_command_handler: ai_handler,
          deliver_to_main_session: ->(**) { raise "must not route to workspace" },
          restart_coordinator: coordinator.restart,
          update_and_restart: coordinator.update,
          work_items_status_fn: ->(msg:) { status_calls << msg },
          config: instance_double(WorkCoordinator::Config, matches_role?: true)
        )
      end

      let(:msg) { { work_item_ref: "home:work-items", body: "status", received_at: Time.now } }
      let(:messages) { [msg] }

      it "dispatches to status rather than routing to a workspace pane" do
        receiver.start { |m| m }
        expect(status_calls).not_to be_empty
        expect(ai_handler_calls).to be_empty
      end
    end
  end
end
