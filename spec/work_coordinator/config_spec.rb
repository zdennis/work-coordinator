# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe WorkCoordinator::Config do
  subject(:config) { described_class.new(config_path) }

  let(:tmpdir) { Dir.mktmpdir }
  let(:config_path) { File.join(tmpdir, "config.yml") }

  after { FileUtils.remove_entry(tmpdir) }

  describe "#exist?" do
    it "returns false when the file is absent" do
      expect(config.exist?).to be(false)
    end

    it "returns true after the file is created" do
      config.write_defaults!
      expect(config.exist?).to be(true)
    end
  end

  describe "#write_defaults!" do
    it "writes the config file" do
      config.write_defaults!
      expect(File.exist?(config_path)).to be(true)
    end

    it "includes the default ai_command in the written file" do
      config.write_defaults!
      content = File.read(config_path)
      expect(content).to include("ai_command")
      expect(content).to include(WorkCoordinator::Config::DEFAULT_AI_COMMAND)
    end

    it "creates parent directories if they do not exist" do
      nested_path = File.join(tmpdir, "a", "b", "config.yml")
      described_class.new(nested_path).write_defaults!
      expect(File.exist?(nested_path)).to be(true)
    end

    it "is idempotent: does not overwrite when the file already exists" do
      config.write_defaults!
      File.write(config_path, "ai_command: custom-ai")

      config.write_defaults!
      expect(File.read(config_path)).to include("custom-ai")
    end
  end

  describe "#ai_command" do
    it "returns the default when the config file does not exist" do
      expect(config.ai_command).to eq(WorkCoordinator::Config::DEFAULT_AI_COMMAND)
    end

    it "returns the default when the config file was created with defaults" do
      config.write_defaults!
      expect(config.ai_command).to eq(WorkCoordinator::Config::DEFAULT_AI_COMMAND)
    end

    it "returns the value from the config file when it has been customized" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: my-ai --flag\n")
      expect(config.ai_command).to eq("my-ai --flag")
    end
  end

  describe ".config_dir" do
    it "defaults to ~/.config/work-coordinator" do
      dir = described_class.config_dir
      expect(dir).to end_with("/.config/work-coordinator")
    end

    it "respects XDG_CONFIG_HOME" do
      allow(ENV).to receive(:fetch).with("XDG_CONFIG_HOME", anything).and_return("/custom/xdg")
      expect(described_class.config_dir).to eq("/custom/xdg/work-coordinator")
    end
  end

  describe ".default_config_path" do
    it "is config.yml inside the config_dir" do
      expect(described_class.default_config_path).to eq(
        File.join(described_class.config_dir, "config.yml")
      )
    end
  end
end
