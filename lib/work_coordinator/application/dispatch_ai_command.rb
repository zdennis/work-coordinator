# frozen_string_literal: true

require "work_coordinator/domain/github_url_extractor"

module WorkCoordinator
  module Application
    class DispatchAiCommand
      Result = Data.define(:dispatched, :project, :summary, :failure_reason)

      def initialize(
        ai_command_runner:,
        message_sender:,
        aliases: {},
        instruction_context: "",
        auto_launch_workspace: false,
        workspace_launch_timeout_seconds: 20,
        sleep_fn: method(:sleep)
      )
        @ai_command_runner              = ai_command_runner
        @message_sender                 = message_sender
        @aliases                        = aliases
        @instruction_context            = instruction_context
        @auto_launch_workspace          = auto_launch_workspace
        @workspace_launch_timeout_seconds = workspace_launch_timeout_seconds
        @sleep_fn = sleep_fn
      end

      def call(body:)
        repo = Domain::GithubUrlExtractor.new(body).repo_name
        repo ? url_dispatch(repo: repo, body: body) : ai_dispatch(body: body)
      end

      private

      def url_dispatch(repo:, body:)
        resolved = resolve_alias(repo)
        project  = resolved || fuzzy_match(repo, @ai_command_runner.list_all_projects)
        return no_workspace_result(repo, body) if project.nil?

        if dormant?(project)
          return dormant_workspace_result(project) unless @auto_launch_workspace
          return launch_timeout_result(project) unless wait_for_launch(project)
        end

        run_and_notify(project: project, body: body)
      end

      def ai_dispatch(body:)
        keyword  = @ai_command_runner.extract_project(body: body)
        resolved = resolve_alias(keyword)
        project  = resolved || fuzzy_match(keyword, @ai_command_runner.list_projects)
        return no_workspace_result(keyword, body) if project.nil?

        run_and_notify(project: project, body: body)
      end

      def dormant?(project)
        !@ai_command_runner.list_projects.include?(project)
      end

      def wait_for_launch(project)
        @ai_command_runner.launch_workspace(name: project)
        deadline = Time.now + @workspace_launch_timeout_seconds
        loop do
          @sleep_fn.call(2)
          return true if @ai_command_runner.list_projects.include?(project)
          return false if Time.now >= deadline
        end
      end

      def dormant_workspace_result(project)
        msg = "Workspace '#{project}' is dormant. Enable auto_launch_workspace in config to launch it automatically."
        @message_sender.send_message(to: nil, body: msg, conversation_id: nil)
        Result.new(dispatched: false, project: project, summary: nil, failure_reason: :dormant_workspace)
      end

      def launch_timeout_result(project)
        msg = "Workspace #{project} did not start within #{@workspace_launch_timeout_seconds}s"
        @message_sender.send_message(to: nil, body: msg, conversation_id: nil)
        Result.new(dispatched: false, project: project, summary: nil, failure_reason: :launch_timeout)
      end

      def no_workspace_result(keyword, body)
        @message_sender.send_message(
          to: nil,
          body: "No workspace found matching '#{keyword}' for: #{body}",
          conversation_id: nil
        )
        Result.new(dispatched: false, project: nil, summary: nil, failure_reason: :no_workspace)
      end

      def run_and_notify(project:, body:)
        instructions = build_instructions(body)
        output  = @ai_command_runner.run_project(project: project, instructions: instructions)
        summary = @ai_command_runner.summarize(text: output)
        @message_sender.send_message(to: nil, body: summary, conversation_id: nil)
        Result.new(dispatched: true, project: project, summary: summary, failure_reason: nil)
      end

      def resolve_alias(keyword)
        return nil if keyword.nil? || keyword.empty?

        @aliases[keyword.strip.upcase]
      end

      def build_instructions(body)
        return body if @instruction_context.nil? || @instruction_context.strip.empty?

        "#{body}\n\n#{@instruction_context}"
      end

      def normalize(str)
        str.gsub("-", "_")
      end

      def fuzzy_match(keyword, projects)
        return nil if keyword.nil? || keyword.empty?

        needle = normalize(keyword.downcase.strip)
        match_candidates(projects, needle)
          .min_by { |_, name| (name.length - needle.length).abs }
          &.first
      end

      def match_candidates(projects, needle)
        projects
          .map { |p| [p, normalize(p.downcase)] }
          .select { |_, name| name.include?(needle) || needle.include?(name) }
      end
    end
  end
end
