# frozen_string_literal: true

require "work_coordinator/ports/ai_command_runner"

module WorkCoordinator
  module Adapters
    class FakeAiCommandRunner
      include Ports::AiCommandRunner

      attr_reader :extract_project_calls, :run_project_calls, :launch_workspace_calls

      def initialize(
        extract_project_result: "",
        list_projects_result: [],
        list_projects_results: nil,
        list_all_projects_result: nil,
        run_project_result: "fake output",
        summarize_result: "Fake summary."
      )
        @extract_project_result         = extract_project_result
        @list_projects_result           = list_projects_result
        @list_projects_results          = list_projects_results
        @list_projects_call_count       = 0
        @list_all_projects_result_given = list_all_projects_result
        @run_project_result             = run_project_result
        @summarize_result               = summarize_result
        @extract_project_calls          = []
        @run_project_calls              = []
        @launch_workspace_calls         = []
      end

      def extract_project(body:)
        @extract_project_calls << body
        @extract_project_result
      end

      def list_projects
        if @list_projects_results
          idx = [@list_projects_call_count, @list_projects_results.length - 1].min
          @list_projects_call_count += 1
          @list_projects_results[idx].dup
        else
          @list_projects_result.dup
        end
      end

      def list_all_projects
        (@list_all_projects_result_given || @list_projects_result).dup
      end

      def launch_workspace(name:)
        @launch_workspace_calls << name
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
