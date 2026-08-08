# frozen_string_literal: true

require "open3"
require "shellwords"
require "work_coordinator/ports/ai_command_runner"

module WorkCoordinator
  module Adapters
    class ClaudeWorkspaceCommandRunner
      include Ports::AiCommandRunner

      EXTRACT_PROMPT = "Extract only the project name or workspace keyword from this " \
                       "instruction. Return just the keyword, no explanation: "
      SUMMARIZE_PROMPT = "Summarize the following output in 1 to 3 sentences: "

      def initialize(
        claude_bin: "claude",
        workspace_bin: "workspace"
      )
        @claude_bin    = claude_bin
        @workspace_bin = workspace_bin
      end

      def extract_project(body:)
        stdout, status = run(@claude_bin, "-p", "#{EXTRACT_PROMPT}#{body}")
        raise "claude extract_project failed" unless status.success?

        stdout.strip
      end

      def list_projects
        stdout, status = run(@workspace_bin, "list")
        raise "workspace list failed" unless status.success?

        stdout.lines.map(&:strip).reject(&:empty?)
      end

      def run_project(project:, instructions:)
        command = "#{@claude_bin} -p #{Shellwords.escape(instructions)}"
        stdout, status = run(@workspace_bin, "run", project, command,
                             "--split", "--wait", "--close")
        raise "workspace run failed (exit #{status.exitstatus})" unless status.success?

        stdout
      end

      def summarize(text:)
        stdout, status = run(@claude_bin, "-p", "#{SUMMARIZE_PROMPT}#{text}")
        raise "claude summarize failed" unless status.success?

        stdout.strip
      end

      private

      def run(*cmd)
        Open3.capture2e(*cmd)
      end
    end
  end
end
