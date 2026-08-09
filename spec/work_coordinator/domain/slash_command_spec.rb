# frozen_string_literal: true

require "work_coordinator/domain/slash_command"

RSpec.describe WorkCoordinator::Domain::SlashCommand do
  subject(:command) { described_class.new(body) }

  # --- attribute parsing ---

  context "with '/build GE add OAuth support'" do
    let(:body) { "/build GE add OAuth support" }

    it { expect(command.verb).to eq("build") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.args).to eq("add OAuth support") }
  end

  context "with '/clear GE'" do
    let(:body) { "/clear GE" }

    it { expect(command.verb).to eq("clear") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.args).to be_nil }
  end

  context "with '/stop GE'" do
    let(:body) { "/stop GE" }

    it { expect(command.verb).to eq("stop") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.args).to be_nil }
  end

  # --- recognized? ---

  describe "#recognized?" do
    WorkCoordinator::Domain::SlashCommand::KNOWN_VERBS.each do |verb|
      it "is true for /#{verb}" do
        expect(described_class.new("/#{verb} GE").recognized?).to be true
      end
    end

    it "is false for an unknown verb" do
      expect(described_class.new("/unknown GE").recognized?).to be false
    end

    it "is false when body has no leading slash" do
      expect(described_class.new("build GE foo").recognized?).to be false
    end

    it "is false for empty string" do
      expect(described_class.new("").recognized?).to be false
    end
  end

  # --- instructions ---

  describe "#instructions" do
    it "build with args" do
      result = described_class.new("/build GE add OAuth support").instructions
      expect(result).to eq("We're building a feature: add OAuth support")
    end

    it "build without args" do
      expect(described_class.new("/build GE").instructions).to eq("Build a feature")
    end

    it "research with args" do
      result = described_class.new("/research GE authentication patterns").instructions
      expect(result).to eq("Research authentication patterns")
    end

    it "research without args" do
      expect(described_class.new("/research GE").instructions).to eq("Research the current topic")
    end

    it "clear" do
      expect(described_class.new("/clear GE").instructions).to eq("/clear")
    end

    it "test with args" do
      expect(described_class.new("/test GE user model").instructions).to eq("Run tests: user model")
    end

    it "test without args" do
      expect(described_class.new("/test GE").instructions).to eq("Run the test suite")
    end

    it "fix with args" do
      expect(described_class.new("/fix GE the login timeout").instructions).to eq("Fix: the login timeout")
    end

    it "fix without args" do
      expect(described_class.new("/fix GE").instructions).to eq("Fix the current issue")
    end

    it "review with args" do
      expect(described_class.new("/review GE billing module").instructions).to eq("Review: billing module")
    end

    it "review without args" do
      expect(described_class.new("/review GE").instructions).to eq("Review the current changes")
    end

    it "commit with args" do
      expect(described_class.new("/commit GE fix login bug").instructions).to eq("Commit: fix login bug")
    end

    it "commit without args" do
      expect(described_class.new("/commit GE").instructions).to eq("Commit the current changes")
    end

    it "push" do
      expect(described_class.new("/push GE").instructions).to eq("Push the current branch")
    end

    it "pr with args" do
      result = described_class.new("/pr GE add OAuth support").instructions
      expect(result).to eq("Open a pull request: add OAuth support")
    end

    it "pr without args" do
      expect(described_class.new("/pr GE").instructions).to eq("Open a pull request")
    end

    it "stop" do
      expect(described_class.new("/stop GE").instructions).to eq("C-c")
    end

    it "raises for an unrecognized verb that somehow bypasses recognized?" do
      cmd = described_class.new("/build GE foo")
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

  context "with no leading slash (e.g. 'build GE foo')" do
    let(:body) { "build GE foo" }

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

  # --- case-insensitive verb ---

  context "with uppercase verb '/BUILD GE foo'" do
    let(:body) { "/BUILD GE foo" }

    it "normalizes verb to lowercase" do
      expect(command.verb).to eq("build")
    end

    it { is_expected.to be_recognized }
  end
end
