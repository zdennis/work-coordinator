# frozen_string_literal: true

module WorkCoordinator
  module Adapters
    # Turns an inbound AI-command message into either a query response or a
    # dispatched command, reporting progress on stdout. This is the glue the
    # receiver calls; the use cases themselves stay silent.
    class ConsoleAiCommandHandler
      def initialize(handle_query:, dispatch_ai_command:, message_sender:)
        @handle_query = handle_query
        @dispatch_ai_command = dispatch_ai_command
        @message_sender = message_sender
      end

      # @param msg [Hash] inbound message with `:work_item_ref` and `:body`
      # @return [void]
      def call(msg)
        body = "#{msg[:work_item_ref]} #{msg[:body]}".strip
        return if handle_query?(body)

        dispatch(body)
      rescue StandardError => e
        warn "Error dispatching AI command: #{e.message}"
      end

      private

      def handle_query?(body)
        response = @handle_query.call(body: body)
        return false unless response

        @message_sender.send_message(to: nil, body: response, conversation_id: nil)
        puts "Query handled: #{body.split.first}"
        true
      end

      def dispatch(body)
        puts "AI command: #{body}"
        result = @dispatch_ai_command.call(body: body)
        if result.dispatched
          puts "AI command dispatched to '#{result.project}': #{result.summary}"
        else
          puts "AI command unmatched (#{result.failure_reason}): #{body}"
        end
      end
    end
  end
end
