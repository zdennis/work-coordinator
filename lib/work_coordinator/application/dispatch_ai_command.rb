# frozen_string_literal: true

require "work_coordinator/domain/github_url_extractor"

module WorkCoordinator
  module Application
    class DispatchAiCommand
      Result = Data.define(:dispatched, :project, :summary, :failure_reason)

      def initialize(ai_command_runner:, message_sender:, aliases: {}, instruction_context: "")
        @ai_command_runner   = ai_command_runner
        @message_sender      = message_sender
        @aliases             = aliases
        @instruction_context = instruction_context
      end

      def call(body:)
        keyword = extract_keyword(body)
        resolved = resolve_alias(keyword)
        project = resolved || fuzzy_match(keyword, @ai_command_runner.list_projects)
        return no_workspace_result(keyword, body) if project.nil?

        run_and_notify(project: project, body: body)
      end

      private

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

      def extract_keyword(body)
        repo = Domain::GithubUrlExtractor.new(body).repo_name
        return repo if repo

        @ai_command_runner.extract_project(body: body)
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
