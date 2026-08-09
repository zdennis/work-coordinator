# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe WorkCoordinator::Adapters::ClaudeWorkspaceCommandRunner do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config_path) { File.join(tmpdir, "config.yml") }

  after { FileUtils.remove_entry(tmpdir) }

  def build_runner(config_path: self.config_path, workspace_bin: "workspace")
    described_class.new(config_path: config_path, workspace_bin: workspace_bin)
  end

  describe "auto-init" do
    it "creates the config file when it does not exist and continues" do
      runner = build_runner
      allow(Open3).to receive(:capture2e).and_return(["myproject\n", double(success?: true)])

      expect { runner.list_projects }.to output(/Running init/).to_stdout
      expect(File.exist?(config_path)).to be(true)
    end

    it "does not print the init message when the config already exists" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner

      allow(Open3).to receive(:capture2e).and_return(["project\n", double(success?: true)])

      expect { runner.list_projects }.not_to output(/Running init/).to_stdout
    end
  end

  describe "#extract_project" do
    it "splits ai_command and passes the prompt as a trailing argument" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner

      captured_cmd = nil
      allow(Open3).to receive(:capture2e) do |*cmd|
        captured_cmd = cmd
        ["auth\n", double(success?: true)]
      end

      runner.extract_project(body: "fix the auth service")

      expect(captured_cmd.first(2)).to eq(["my-ai", "-p"])
      expect(captured_cmd.last).to start_with(WorkCoordinator::Adapters::ClaudeWorkspaceCommandRunner::EXTRACT_PROMPT)
    end

    it "raises when the command fails" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner

      allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])

      expect { runner.extract_project(body: "anything") }.to raise_error(RuntimeError, /failed/)
    end
  end

  describe "#list_projects" do
    it "calls workspace list and returns trimmed non-empty lines" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).with("ws", "list").and_return(
        ["auth-service\nacme-billing\n", double(success?: true)]
      )

      expect(runner.list_projects).to eq(%w[auth-service acme-billing])
    end

    it "raises when workspace list fails" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])

      expect { runner.list_projects }.to raise_error(RuntimeError, /workspace list failed/)
    end
  end

  describe "#summarize" do
    it "splits ai_command and passes the summary prompt" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner

      captured_cmd = nil
      allow(Open3).to receive(:capture2e) do |*cmd|
        captured_cmd = cmd
        ["A summary.\n", double(success?: true)]
      end

      result = runner.summarize(text: "some output")

      expect(captured_cmd.first(2)).to eq(["my-ai", "-p"])
      expect(result).to eq("A summary.")
    end
  end

  describe "#list_all_projects" do
    it "calls workspace list --all and returns trimmed non-empty lines" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).with("ws", "list", "--all").and_return(
        ["auth-service\ndormant-project\n", double(success?: true)]
      )

      expect(runner.list_all_projects).to eq(%w[auth-service dormant-project])
    end

    it "raises when workspace list --all fails" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])

      expect { runner.list_all_projects }.to raise_error(RuntimeError, /workspace list --all failed/)
    end
  end

  describe "#list_all_projects_with_urls" do
    it "calls workspace list --all --show-urls --json and parses JSON" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).with("ws", "list", "--all", "--show-urls", "--json").and_return(
        [%([{"name":"auth-service","url":"https://github.com/acme/auth-service"}]\n), double(success?: true)]
      )

      expect(runner.list_all_projects_with_urls).to eq(
        [{ name: "auth-service", url: "https://github.com/acme/auth-service" }]
      )
    end

    it "handles null url in JSON" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).with("ws", "list", "--all", "--show-urls", "--json").and_return(
        [%([{"name":"dormant-project","url":null}]\n), double(success?: true)]
      )

      expect(runner.list_all_projects_with_urls).to eq([{ name: "dormant-project", url: nil }])
    end

    it "raises when command fails" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])

      expect { runner.list_all_projects_with_urls }.to raise_error(
        RuntimeError, /workspace list --all --show-urls --json failed/
      )
    end
  end

  describe "#launch_workspace" do
    it "calls workspace launch with the project name" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      captured_cmd = nil
      allow(Open3).to receive(:capture2e) do |*cmd|
        captured_cmd = cmd
        ["", double(success?: true)]
      end

      runner.launch_workspace(name: "my-project")

      expect(captured_cmd).to eq(%w[ws launch my-project])
    end

    it "raises when workspace launch fails" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])

      expect { runner.launch_workspace(name: "bad-project") }.to raise_error(RuntimeError, /workspace launch failed/)
    end
  end

  describe "#run_project" do
    it "builds the command string from ai_command and passes it to workspace run" do
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, "ai_command: \"my-ai -p\"\n")
      runner = build_runner(workspace_bin: "ws")

      captured_cmd = nil
      allow(Open3).to receive(:capture2e) do |*cmd|
        captured_cmd = cmd
        ["output\n", double(success?: true, exitstatus: 0)]
      end

      runner.run_project(project: "auth-service", instructions: "do the thing")

      expect(captured_cmd[0]).to eq("ws")
      expect(captured_cmd[1]).to eq("run")
      expect(captured_cmd[2]).to eq("auth-service")
      expect(captured_cmd[3]).to start_with("my-ai -p ")
    end
  end
end
