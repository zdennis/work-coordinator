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
        sleep_fn: method(:sleep),
        clock_fn: -> { Time.now }
      )
        @ai_command_runner                = ai_command_runner
        @message_sender                   = message_sender
        @aliases                          = aliases
        @instruction_context              = instruction_context
        @auto_launch_workspace            = auto_launch_workspace
        @workspace_launch_timeout_seconds = workspace_launch_timeout_seconds
        @sleep_fn                         = sleep_fn
        @clock_fn                         = clock_fn
      end

      def call(body:)
        repo = Domain::GithubUrlExtractor.new(body).repo_name
        repo ? url_dispatch(repo: repo, body: body) : ai_dispatch(body: body)
      end

      private

      def url_dispatch(repo:, body:)
        active_projects = @ai_command_runner.list_projects
        project         = resolve_url_project(repo: repo, body: body)
        return no_workspace_result(repo, body) if project.nil?

        unless active_projects.include?(project)
          return dormant_workspace_result(project) unless @auto_launch_workspace
          return launch_timeout_result(project) unless wait_for_launch(project)
        end

        run_and_notify(project: project, body: body)
      end

      def resolve_url_project(repo:, body:)
        resolved = resolve_alias(repo)
        return resolved if resolved

        owner_repo         = Domain::GithubUrlExtractor.new(body).owner_repo
        projects_with_urls = @ai_command_runner.list_all_projects_with_urls
        all_projects       = projects_with_urls.map { |p| p[:name] }
        url_match(owner_repo, projects_with_urls) || fuzzy_match(repo, all_projects)
      end

      def ai_dispatch(body:)
        keyword  = @ai_command_runner.extract_project(body: body)
        resolved = resolve_alias(keyword)
        project  = resolved || fuzzy_match(keyword, @ai_command_runner.list_projects)
        return no_workspace_result(keyword, body) if project.nil?

        run_and_notify(project: project, body: body)
      end

      def wait_for_launch(project)
        @ai_command_runner.launch_workspace(name: project)
        deadline = @clock_fn.call + @workspace_launch_timeout_seconds
        loop do
          @sleep_fn.call(2)
          return true if @ai_command_runner.list_projects.include?(project)
          return false if @clock_fn.call >= deadline
        end
      end

      def dormant_workspace_result(project)
        msg = "Workspace '#{project}' is not currently running. " \
              "Enable auto_launch_workspace in config to launch it automatically."
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

      def url_match(owner_repo, projects_with_urls)
        return nil if owner_repo.nil?

        candidates = projects_with_urls.select { |w| normalize_git_url(w[:url]) == owner_repo }
        return nil if candidates.empty?

        best_url_candidate(candidates, owner_repo.split("/").last)
      end

      def best_url_candidate(candidates, repo_name)
        exact = candidates.find { |w| w[:name] == repo_name }
        return exact[:name] if exact

        candidates.min_by { |w| (w[:name].length - repo_name.length).abs }[:name]
      end

      def normalize_git_url(url)
        return nil if url.nil?

        u     = url.sub(/\.git$/, "").sub(%r{/+$}, "")
        parts = u.split(%r{[:/]})
        parts.last(2).join("/")
      end
    end
  end
end
