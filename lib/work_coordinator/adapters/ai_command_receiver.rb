# frozen_string_literal: true

require "logger"
require "work_coordinator/ports/message_receiver"
require "work_coordinator/application/route_message"
require "work_coordinator/domain/ai_command"
require "work_coordinator/domain/role_token"
require "work_coordinator/domain/slash_command"

module WorkCoordinator
  module Adapters
    class AiCommandReceiver
      include Ports::MessageReceiver

      def initialize(inner:, ai_command_handler:, deliver_to_main_session:, restart_coordinator:,
                     update_and_restart:, register_command_work_item: nil, slash_commands_enabled: true,
                     logger: Logger.new(IO::NULL))
        @inner                      = inner
        @ai_command_handler         = ai_command_handler
        @deliver_to_main_session    = deliver_to_main_session
        @register_command_work_item = register_command_work_item
        @restart_coordinator        = restart_coordinator
        @update_and_restart         = update_and_restart
        @slash_commands_enabled     = slash_commands_enabled
        @logger                     = logger
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
        return if @slash_commands_enabled && slash_command_dispatched?(body)

        command = Domain::AiCommand.new(body)
        @logger.debug "AiCommand parsed: verb=#{command.verb.inspect} " \
                      "workspace=#{command.workspace.inspect} " \
                      "instructions=#{command.instructions.inspect}"
        @logger.debug "Routing: #{command.send_to_main_session? ? 'main session' : 'ai command handler'}"
        if command.send_to_main_session?
          deliver_to_main(workspace_name: command.workspace, instructions: command.instructions)
        else
          @ai_command_handler.call(msg)
        end
      end

      # Returns true when the body was handled as a slash command.
      def slash_command_dispatched?(body)
        slash = Domain::SlashCommand.new(body)

        if slash.coordinator_command?
          dispatch_coordinator_command(slash)
        elsif slash.recognized?
          deliver_to_main(
            workspace_name: slash.workspace,
            instructions: slash.instructions,
            work_item_ref: register_work_item_for(slash, body)
          )
        else
          return false
        end

        true
      end

      def dispatch_coordinator_command(slash)
        case slash.verb
        when "restart" then @restart_coordinator.call
        when "update"  then @update_and_restart.call
        end
      end

      # Every dispatched slash command gets an identity before it is forwarded.
      # Returns nil when no registrar is wired, leaving delivery unreferenced.
      def register_work_item_for(slash, body)
        return nil unless @register_command_work_item

        @register_command_work_item.call(title: body, workspace_name: slash.workspace).external_reference
      end

      def deliver_to_main(workspace_name:, instructions:, work_item_ref: nil)
        @deliver_to_main_session.call(
          workspace_name: workspace_name,
          instructions: instructions,
          work_item_ref: work_item_ref,
          recipient: nil # intentional: ack goes to the default WC_RECIPIENT; :from is not forwarded
        )
      end
    end
  end
end
