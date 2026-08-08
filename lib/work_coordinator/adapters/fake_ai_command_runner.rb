# frozen_string_literal: true

require "work_coordinator/ports/ai_command_runner"

module WorkCoordinator
  module Adapters
    class FakeAiCommandRunner
      include Ports::AiCommandRunner

      attr_reader :extract_project_calls, :run_project_calls

      def initialize(
        extract_project_result: "",
        list_projects_result: [],
        run_project_result: "fake output",
        summarize_result: "Fake summary."
      )
        @extract_project_result = extract_project_result
        @list_projects_result   = list_projects_result
        @run_project_result     = run_project_result
        @summarize_result       = summarize_result
        @extract_project_calls  = []
        @run_project_calls      = []
      end

      def extract_project(body:)
        @extract_project_calls << body
        @extract_project_result
      end

      def list_projects
        @list_projects_result.dup
      end

      def run_project(project:, instructions:)
        @run_project_calls << { project: project, instructions: instructions }
        @run_project_result
      end

      def summarize(**)
        @summarize_result
      end
    end
  end
end
