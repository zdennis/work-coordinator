# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"
require "work_coordinator/application/route_message"

module WorkCoordinator
  module Adapters
    class AiCommandReceiver
      include Ports::MessageReceiver

      def initialize(inner:, ai_command_handler:)
        @inner              = inner
        @ai_command_handler = ai_command_handler
      end

      def start(&block)
        @inner.start do |msg|
          raw = "#{msg[:work_item_ref]} #{msg[:body]}".strip
          if routable?(raw)
            block.call(msg)
          else
            @ai_command_handler.call(msg)
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
    end
  end
end
