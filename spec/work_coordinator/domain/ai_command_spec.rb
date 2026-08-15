# frozen_string_literal: true

require "work_coordinator/domain/ai_command"

RSpec.describe WorkCoordinator::Domain::AiCommand do
  subject(:command) { described_class.new(body) }

  # --- attribute parsing ---

  context "with 'claude MS - add validation'" do
    let(:body) { "claude MS - add validation" }

    it { expect(command.verb).to eq("claude") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.instructions).to eq("add validation") }
  end

  context "with 'main my-service - refactor auth'" do
    let(:body) { "main my-service - refactor auth" }

    it { expect(command.verb).to eq("main") }
    it { expect(command.workspace).to eq("my-service") }
    it { expect(command.instructions).to eq("refactor auth") }
  end

  context "with 'new MS - open a bash pane'" do
    let(:body) { "new MS - open a bash pane" }

    it { expect(command.verb).to eq("new") }
    it { expect(command.workspace).to eq("MS") }
  end

  context "with 'bash MS - run tests'" do
    let(:body) { "bash MS - run tests" }

    it { expect(command.verb).to eq("bash") }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.instructions).to eq("run tests") }
  end

  context "without a verb: 'MS - add validation'" do
    let(:body) { "MS - add validation" }

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.instructions).to eq("add validation") }
  end

  context "without verb or separator: 'add validation to the form'" do
    let(:body) { "add validation to the form" }

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to be_nil }
    it { expect(command.instructions).to eq("add validation to the form") }
  end

  context "with multiline instructions" do
    let(:body) { "claude MS - step one\nstep two" }

    it { expect(command.instructions).to eq("step one\nstep two") }
  end

  # --- malformed inputs ---

  context "with 'claude MS' (verb present, no separator)" do
    let(:body) { "claude MS" }

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to be_nil }
    it { expect(command.instructions).to eq("claude MS") }
    it { is_expected.not_to be_send_to_main_session }
  end

  context "with 'claude - do something' (verb present, no workspace before dash)" do
    # PATTERN requires WORKSPACE before the dash; "claude - do something" matches with
    # verb=nil, workspace="claude" (the verb token is parsed as the workspace because
    # the optional verb group is absent). send_to_main_session? is false since verb is nil.
    let(:body) { "claude - do something" }

    it "does not raise" do
      expect { command }.not_to raise_error
    end

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to eq("claude") }
    it { expect(command.instructions).to eq("do something") }
    it { is_expected.not_to be_send_to_main_session }
  end

  context "with 'claude' alone" do
    let(:body) { "claude" }

    it "does not raise" do
      expect { command }.not_to raise_error
    end

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to be_nil }
    it { is_expected.not_to be_send_to_main_session }
  end

  context "with 'MS - instructions' (no verb, workspace and instructions present)" do
    let(:body) { "MS - instructions" }

    it { expect(command.verb).to be_nil }
    it { expect(command.workspace).to eq("MS") }
    it { expect(command.instructions).to eq("instructions") }
    it { is_expected.not_to be_send_to_main_session }
  end

  context "with mixed case verb: 'CLAUDE MS - foo'" do
    let(:body) { "CLAUDE MS - foo" }

    it "normalizes verb to lowercase" do
      expect(command.verb).to eq("claude")
    end

    it { is_expected.to be_send_to_main_session }
  end

  # --- send_to_main_session? ---

  describe "#send_to_main_session?" do
    it "is true for verb 'claude'" do
      expect(described_class.new("claude MS - foo").send_to_main_session?).to be true
    end

    it "is true for verb 'main'" do
      expect(described_class.new("main MS - foo").send_to_main_session?).to be true
    end

    it "is false for verb 'new'" do
      expect(described_class.new("new MS - foo").send_to_main_session?).to be false
    end

    it "is false for verb 'bash'" do
      expect(described_class.new("bash MS - foo").send_to_main_session?).to be false
    end

    it "is false when no verb is present" do
      expect(described_class.new("MS - foo").send_to_main_session?).to be false
    end

    it "is false when body has no separator" do
      expect(described_class.new("add some feature").send_to_main_session?).to be false
    end
  end

  # --- new_session? ---

  describe "#new_session?" do
    it "is true for verb 'new'" do
      expect(described_class.new("new MS - foo").new_session?).to be true
    end

    it "is true when body has no verb or separator (free-form dispatch)" do
      expect(described_class.new("add some feature").new_session?).to be true
    end

    it "is false for verb 'claude'" do
      expect(described_class.new("claude MS - foo").new_session?).to be false
    end
  end

  # --- bash_session? ---

  describe "#bash_session?" do
    it "is true for verb 'bash'" do
      expect(described_class.new("bash MS - foo").bash_session?).to be true
    end

    it "is false for any other verb" do
      expect(described_class.new("claude MS - foo").bash_session?).to be false
    end

    it "is false when no verb present" do
      expect(described_class.new("MS - foo").bash_session?).to be false
    end
  end
end
