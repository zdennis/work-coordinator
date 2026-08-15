# frozen_string_literal: true

require "work_coordinator/domain/slash_command"

RSpec.describe WorkCoordinator::Domain::SlashCommand do
  subject(:command) { described_class.new(body) }

  # --- attribute parsing ---

  context "with '/build MS add OAuth support'" do
    let(:body) { "/build MS add OAuth support" }

    it { expect(command.verb).to eq("build") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.args).to eq("add OAuth support") }
  end

  context "with '/clear MS'" do
    let(:body) { "/clear MS" }

    it { expect(command.verb).to eq("clear") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.args).to be_nil }
  end

  context "with '/stop MS'" do
    let(:body) { "/stop MS" }

    it { expect(command.verb).to eq("stop") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.args).to be_nil }
  end

  # --- recognized? ---

  describe "#recognized?" do
    pane_verbs = WorkCoordinator::Domain::SlashCommand::KNOWN_VERBS -
                 WorkCoordinator::Domain::SlashCommand::COORDINATOR_VERBS

    pane_verbs.each do |verb|
      it "is true for /#{verb} MS" do
        expect(described_class.new("/#{verb} MS").recognized?).to be true
      end
    end

    WorkCoordinator::Domain::SlashCommand::COORDINATOR_VERBS.each do |verb|
      it "is true for a bare /#{verb}" do
        expect(described_class.new("/#{verb}").recognized?).to be true
      end
    end

    it "is false for an unknown verb" do
      expect(described_class.new("/unknown MS").recognized?).to be false
    end

    it "is false when body has no leading slash" do
      expect(described_class.new("build MS foo").recognized?).to be false
    end

    it "is false for empty string" do
      expect(described_class.new("").recognized?).to be false
    end
  end

  # --- instructions ---

  describe "#instructions" do
    it "build with args" do
      result = described_class.new("/build MS add OAuth support").instructions
      expect(result).to eq("We're building a feature: add OAuth support")
    end

    it "build without args" do
      expect(described_class.new("/build MS").instructions).to eq("Build a feature")
    end

    it "research with args" do
      result = described_class.new("/research MS authentication patterns").instructions
      expect(result).to eq("Research authentication patterns")
    end

    it "research without args" do
      expect(described_class.new("/research MS").instructions).to eq("Research the current topic")
    end

    it "clear" do
      expect(described_class.new("/clear MS").instructions).to eq("/clear")
    end

    it "test with args" do
      expect(described_class.new("/test MS user model").instructions).to eq("Run tests: user model")
    end

    it "test without args" do
      expect(described_class.new("/test MS").instructions).to eq("Run the test suite")
    end

    it "fix with args" do
      expect(described_class.new("/fix MS the login timeout").instructions).to eq("Fix: the login timeout")
    end

    it "fix without args" do
      expect(described_class.new("/fix MS").instructions).to eq("Fix the current issue")
    end

    it "review with args" do
      expect(described_class.new("/review MS billing module").instructions).to eq("Review: billing module")
    end

    it "review without args" do
      expect(described_class.new("/review MS").instructions).to eq("Review the current changes")
    end

    it "commit with args" do
      expect(described_class.new("/commit MS fix login bug").instructions).to eq("Commit: fix login bug")
    end

    it "commit without args" do
      expect(described_class.new("/commit MS").instructions).to eq("Commit the current changes")
    end

    it "push" do
      expect(described_class.new("/push MS").instructions).to eq("Push the current branch")
    end

    it "pr with args" do
      result = described_class.new("/pr MS add OAuth support").instructions
      expect(result).to eq("Open a pull request: add OAuth support")
    end

    it "pr without args" do
      expect(described_class.new("/pr MS").instructions).to eq("Open a pull request")
    end

    it "stop" do
      expect(described_class.new("/stop MS").instructions).to eq("C-c")
    end

    it "raises for an unrecognized verb that somehow bypasses recognized?" do
      cmd = described_class.new("/build MS foo")
      cmd.instance_variable_set(:@verb, "unknown")
      expect { cmd.instructions }.to raise_error(RuntimeError, /instructions not defined/)
    end
  end

  # --- malformed inputs ---

  context "with no workspace (e.g. '/build')" do
    let(:body) { "/build" }

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to be_nil }
    it { is_expected.not_to be_recognized }
  end

  context "with no leading slash (e.g. 'build MS foo')" do
    let(:body) { "build MS foo" }

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to be_nil }
    it { is_expected.not_to be_recognized }
  end

  context "with empty string" do
    let(:body) { "" }

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to be_nil }
    it { is_expected.not_to be_recognized }
  end

  # --- coordinator verbs (no workspace) ---

  describe "coordinator verbs" do
    it "recognizes /restart" do
      expect(described_class.new("/restart")).to be_recognized
    end

    it "treats /restart as a coordinator command" do
      expect(described_class.new("/restart")).to be_coordinator_command
    end

    it "has no pane instructions" do
      expect { described_class.new("/restart").instructions }
        .to raise_error(/No pane instructions for coordinator command: restart/)
    end

    it "recognizes a bare 'restart' with no leading slash" do
      expect(described_class.new("restart")).to be_coordinator_command
    end

    it "recognizes a bare 'update' with no leading slash" do
      expect(described_class.new("update")).to be_coordinator_command
    end

    it "is not recognized when a coordinator verb carries a workspace" do
      expect(described_class.new("/restart MS")).not_to be_recognized
    end

    it "is not recognized when a coordinator verb carries args" do
      expect(described_class.new("/update the readme")).not_to be_recognized
    end

    it "recognizes /update" do
      expect(described_class.new("/update")).to be_recognized
    end

    it "treats /update as a coordinator command" do
      expect(described_class.new("/update")).to be_coordinator_command
    end

    it "has no pane instructions for update either" do
      expect { described_class.new("/update").instructions }
        .to raise_error(/No pane instructions for coordinator command: update/)
    end

    it "parses no workspace or args" do
      command = described_class.new("/restart")
      expect([command.workspace, command.args]).to eq([nil, nil])
    end

    it "is case-insensitive" do
      command = described_class.new("/RESTART")
      expect(command.verb).to eq("restart")
    end

    it "recognizes an uppercase verb" do
      expect(described_class.new("/RESTART")).to be_recognized
    end

    it "tolerates trailing whitespace" do
      expect(described_class.new("/restart  ")).to be_recognized
    end

    it "tolerates leading whitespace" do
      expect(described_class.new("  /update")).to be_recognized
    end

    it "is not a coordinator command for a workspace verb" do
      expect(described_class.new("/build MS")).not_to be_coordinator_command
    end

    it "is not a coordinator command for an unparsed body" do
      expect(described_class.new("")).not_to be_coordinator_command
    end
  end

  # --- regression guard: workspace verbs still require a workspace ---

  describe "workspace verbs without a workspace" do
    workspace_verbs = WorkCoordinator::Domain::SlashCommand::KNOWN_VERBS -
                      WorkCoordinator::Domain::SlashCommand::COORDINATOR_VERBS

    workspace_verbs.each do |verb|
      it "does not recognize a bare /#{verb}" do
        expect(described_class.new("/#{verb}")).not_to be_recognized
      end
    end

    it "leaves the verb unparsed so nothing routes to a nil workspace" do
      expect(described_class.new("/build").verb).to be_nil
    end
  end

  # --- case-insensitive verb ---

  context "with uppercase verb '/BUILD MS foo'" do
    let(:body) { "/BUILD MS foo" }

    it "normalizes verb to lowercase" do
      expect(command.verb).to eq("build")
    end

    it { is_expected.to be_recognized }
  end
end
