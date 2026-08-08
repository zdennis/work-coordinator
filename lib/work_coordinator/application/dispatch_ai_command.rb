# frozen_string_literal: true

module WorkCoordinator
  module Application
    class DispatchAiCommand
      Result = Data.define(:dispatched, :project, :summary, :failure_reason)

      def initialize(ai_command_runner:, message_sender:, aliases: {})
        @ai_command_runner = ai_command_runner
        @message_sender    = message_sender
        @aliases           = aliases
      end

      def call(body:)
        keyword = @ai_command_runner.extract_project(body: body)
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
        output  = @ai_command_runner.run_project(project: project, instructions: body)
        summary = @ai_command_runner.summarize(text: output)
        @message_sender.send_message(to: nil, body: summary, conversation_id: nil)
        Result.new(dispatched: true, project: project, summary: summary, failure_reason: nil)
      end

      def resolve_alias(keyword)
        return nil if keyword.nil? || keyword.empty?

        @aliases[keyword.strip.upcase]
      end

      def fuzzy_match(keyword, projects)
        return nil if keyword.nil? || keyword.empty?

        needle = keyword.downcase.strip
        candidates = projects.select do |p|
          name = p.downcase
          name.include?(needle) || needle.include?(name)
        end
        candidates.min_by { |p| (p.length - needle.length).abs }
      end
    end
  end
end
