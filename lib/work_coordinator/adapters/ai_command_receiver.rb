# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"
require "work_coordinator/application/route_message"
require "work_coordinator/domain/ai_command"

module WorkCoordinator
  module Adapters
    class AiCommandReceiver
      include Ports::MessageReceiver

      def initialize(inner:, ai_command_handler:, deliver_to_main_session:)
        @inner                   = inner
        @ai_command_handler      = ai_command_handler
        @deliver_to_main_session = deliver_to_main_session
      end

      def start(&block)
        @inner.start do |msg|
          # MessagesInboxPoller splits "ai: VERB WORKSPACE - ..." on the first space,
          # putting the verb token into :work_item_ref and the remainder into :body.
          # Reconstruct the full body here so AiCommand can parse the complete string.
          raw = "#{msg[:work_item_ref]} #{msg[:body]}".strip
          if routable?(raw)
            block.call(msg)
          else
            dispatch_ai_message(msg, raw)
          end
        end
      end

      def stop
        @inner.stop
      end

      private

      def routable?(raw)
        Application::RouteMessage::PREFIX_PATTERN.match?(raw) ||
          Application::RouteMessage::REPLY_PATTERN.match?(raw)
      end

      def dispatch_ai_message(msg, body)
        command = Domain::AiCommand.new(body)

        if command.send_to_main_session?
          @deliver_to_main_session.call(
            workspace_name: command.workspace,
            instructions: command.instructions,
            recipient: nil # intentional: ack goes to the default WC_RECIPIENT; :from is not forwarded
          )
        else
          @ai_command_handler.call(msg)
        end
      end
    end
  end
end
