# frozen_string_literal: true

require "open3"
require "shellwords"
require "work_coordinator/ports/ai_command_runner"
require "work_coordinator/config"

module WorkCoordinator
  module Adapters
    class ClaudeWorkspaceCommandRunner
      include Ports::AiCommandRunner

      EXTRACT_PROMPT = "Extract only the project name or workspace keyword from this " \
                       "instruction. Return just the keyword, no explanation: "
      SUMMARIZE_PROMPT = "Summarize the following output in 1 to 3 sentences: "

      def initialize(
        config_path: Config.default_config_path,
        workspace_bin: "workspace"
      )
        @config        = Config.new(config_path)
        @workspace_bin = workspace_bin
      end

      def extract_project(body:)
        stdout, status = run(*ai_command_args, "#{EXTRACT_PROMPT}#{body}")
        raise "ai extract_project failed" unless status.success?

        stdout.strip
      end

      def list_projects
        stdout, status = run(@workspace_bin, "list")
        raise "workspace list failed" unless status.success?

        stdout.lines.map(&:strip).reject(&:empty?)
      end

      def list_all_projects
        stdout, status = run(@workspace_bin, "list", "--all")
        raise "workspace list --all failed" unless status.success?

        stdout.lines.map(&:strip).reject(&:empty?)
      end

      def launch_workspace(name:)
        _, status = run(@workspace_bin, "launch", name)
        raise "workspace launch failed for #{name}" unless status.success?
      end

      def run_project(project:, instructions:)
        command = "#{@config.ai_command} #{Shellwords.escape(instructions)}"
        stdout, status = run(@workspace_bin, "run", project, command,
                             "--split", "--wait", "--close")
        raise "workspace run failed (exit #{status.exitstatus})" unless status.success?

        stdout
      end

      def summarize(text:)
        stdout, status = run(*ai_command_args, "#{SUMMARIZE_PROMPT}#{text}")
        raise "ai summarize failed" unless status.success?

        stdout.strip
      end

      private

      def ai_command_args
        Shellwords.split(@config.ai_command)
      end

      def ensure_config
        return if @config.exist?

        puts "No config file found at #{@config.path}. Running init..."
        @config.write_defaults!
        puts "Created #{@config.path} with defaults."
      end

      def run(*cmd)
        ensure_config
        Open3.capture2e(*cmd)
      end
    end
  end
end
