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
          raw = "#{msg[:work_item_ref]} #{msg[:body]}".strip
          if routable?(raw)
            block.call(msg)
          else
            dispatch_ai_message(msg)
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

      def dispatch_ai_message(msg)
        body    = "#{msg[:work_item_ref]} #{msg[:body]}".strip
        command = Domain::AiCommand.new(body)

        if command.send_to_main_session?
          @deliver_to_main_session.call(
            workspace_name: command.workspace,
            instructions: command.instructions,
            recipient: nil
          )
        else
          @ai_command_handler.call(msg)
        end
      end
    end
  end
end
