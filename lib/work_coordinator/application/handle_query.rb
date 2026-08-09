# frozen_string_literal: true

require "work_coordinator/domain/work_item"
require "work_coordinator/persistence/models/resource_lease_record"

module WorkCoordinator
  module Application
    # Intercepts `ai:` messages before they reach DispatchAiCommand.
    #
    # When the message body matches a known query keyword, returns a plain-text
    # response string (to be sent back via iMessage). When it does not match,
    # returns nil so the message falls through to DispatchAiCommand unchanged.
    class HandleQuery # rubocop:disable Metrics/ClassLength
      COMMAND_DESCRIPTIONS = {
        "init" => "create config file",
        "alias" => "manage aliases",
        "register" => "create work item",
        "start" => "activate work item",
        "status" => "list all work items",
        "send" => "send message via socket",
        "run" => "start the daemon",
        "notify" => "send a notification"
      }.freeze

      SHORTHAND_STATE_MAP = {
        "waiting" => :waiting_for_human
      }.freeze

      # @param work_item_repo [Ports::WorkItemRepository]
      # @param event_store [#recent]
      # @param agent_session [Ports::AgentSession]
      # @param config [WorkCoordinator::Config]
      # @param message_sender [Ports::MessageSender]
      def initialize(work_item_repo:, event_store:, agent_session:, config:, message_sender:)
        @work_item_repo = work_item_repo
        @event_store    = event_store
        @agent_session  = agent_session
        @config         = config
        @message_sender = message_sender
      end

      # @param body [String] the message body to match against
      # @return [String, nil] response text, or nil if no query matched
      def call(body:) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize
        case body.strip
        when /\Ahelp\z/i
          help_overview
        when /\Ahelp commands\z/i
          help_commands
        when /\Ahelp (.+)\z/i
          help_command(Regexp.last_match(1).strip)
        when /\Aalias(?:es)?\z/i
          list_aliases
        when /\Aconfig\z/i
          show_config
        when /\Astatus\z/i
          status_all
        when /\Astatus (.+)\z/i
          status_filtered(Regexp.last_match(1).strip)
        when /\A(blocked|waiting|active|created|completed|abandoned|ready)\z/i
          shorthand_status(Regexp.last_match(1).downcase)
        when /\Aitem (.+)\z/i
          item_detail(Regexp.last_match(1).strip)
        when /\Arecent(?:\s+(\d+))?\z/i
          recent_events(Regexp.last_match(1)&.to_i || 5)
        when /\Apanes\z/i
          list_panes
        when /\Aleases\z/i
          list_leases
        end
      end

      private

      def help_overview # rubocop:disable Metrics/MethodLength
        <<~TEXT.chomp
          ai: queries:
            help [cmd]     usage for a command
            aliases        configured aliases
            config         current settings
            status [s]     work items by state
            blocked/waiting/active  shortcuts
            item REF       one item detail
            recent [n]     last N events
            panes          active tmux panes
            leases         resource leases
          ai: actions:
            claude WORKSPACE - instructions   deliver to main session (pane 1)
            main   WORKSPACE - instructions   alias for claude
            new    WORKSPACE - instructions   spawn new pane (not yet implemented)
            bash   WORKSPACE - instructions   spawn new bash pane (not yet implemented)
                   WORKSPACE - instructions   no verb: LLM extraction pipeline
        TEXT
      end

      def help_commands
        max_len = COMMAND_DESCRIPTIONS.keys.map(&:length).max
        lines = COMMAND_DESCRIPTIONS.map do |name, desc|
          "  #{name.ljust(max_len)}  #{desc}"
        end
        "CLI commands:\n#{lines.join("\n")}"
      end

      def help_command(name)
        match = COMMAND_DESCRIPTIONS.keys.find do |k|
          k.downcase.include?(name.downcase)
        end

        if match
          desc = COMMAND_DESCRIPTIONS[match]
          "#{match}: #{desc}\n" \
            "Usage: work-coordinator #{match} [options]\n" \
            "Run 'work-coordinator #{match} --help' for full usage."
        else
          "Unknown command: #{name}. Try 'ai: help commands' for a list."
        end
      end

      def list_aliases
        aliases = @config.aliases
        if aliases.empty?
          "No aliases configured. Add one with: work-coordinator alias add SHORT project"
        else
          lines = aliases.map { |short, project| "  #{short} -> #{project}" }
          "Aliases (#{aliases.size}):\n#{lines.join("\n")}"
        end
      end

      def show_config
        alias_count = @config.aliases.size
        "Config: ~/.config/work-coordinator/config.yml\naliases: #{alias_count} configured"
      end

      def status_all
        items = @work_item_repo.find_all
        format_work_items(items)
      end

      def status_filtered(filter)
        matched_state = Domain::WORK_ITEM_STATES.find do |s|
          s.to_s.downcase.include?(filter.downcase)
        end

        unless matched_state
          known = Domain::WORK_ITEM_STATES.join(", ")
          return "Unknown state: #{filter}. Known states: #{known}"
        end

        items = @work_item_repo.find_all(status: matched_state)
        format_work_items(items)
      end

      def shorthand_status(keyword)
        state = SHORTHAND_STATE_MAP.fetch(keyword, keyword.to_sym)
        items = @work_item_repo.find_all(status: state)
        format_work_items(items)
      end

      def item_detail(ref) # rubocop:disable Metrics/AbcSize
        item = @work_item_repo.find_all.find do |wi|
          wi.external_reference&.upcase == ref.upcase
        end

        return "No work item with ref: #{ref}" unless item

        lines = ["#{item.external_reference}: #{item.title}"]
        state_line = "state: #{item.state}"
        state_line += "  phase: #{item.phase}" if item.phase
        lines << state_line
        lines << "kind: #{item.kind}  repo: #{item.repository}" if item.repository
        lines << "pane: #{item.workspace_name}" if item.workspace_name
        lines << "updated: #{relative_time(item.updated_at)}"
        lines.join("\n")
      end

      def recent_events(limit)
        events = @event_store.recent(limit: limit)
        return "No events recorded yet." if events.empty?

        lines = events.map do |e|
          age = relative_time(e.occurred_at)
          "#{age.ljust(6)}  #{e.type.to_s.ljust(24)}  #{e.work_item_id}"
        end
        "Recent events (#{events.size}):\n#{lines.join("\n")}"
      end

      def list_panes # rubocop:disable Metrics/MethodLength
        panes = begin
          @agent_session.list_all_panes
        rescue StandardError
          []
        end

        return "No active tmux panes." if panes.empty?

        all_items = @work_item_repo.find_all
        lines = panes.map do |pane|
          item = all_items.find { |wi| wi.workspace_name == pane }
          if item
            "  #{pane}   #{item.external_reference} (#{item.state})"
          else
            "  #{pane}   (unregistered)"
          end
        end
        "Active panes:\n#{lines.join("\n")}"
      end

      def list_leases
        leases = Persistence::Models::ResourceLeaseRecord.where(released_at: nil)
        return "No active leases." if leases.empty?

        lines = leases.map do |lease|
          age = relative_time(lease.created_at)
          "  #{lease.resource_name}: #{lease.work_item_id} (#{age})"
        end
        "Active leases:\n#{lines.join("\n")}"
      end

      def format_work_items(items) # rubocop:disable Metrics/AbcSize
        return "No work items." if items.empty?

        truncated = items.length > 10
        display = items.first(10)
        lines = display.map do |wi|
          state_phase = wi.phase ? "#{wi.state}/#{wi.phase}" : wi.state.to_s
          ref = wi.external_reference || wi.id[0, 8]
          "#{ref.ljust(10)}  #{state_phase.ljust(24)}  #{wi.title}"
        end
        result = "#{items.length} work item#{'s' if items.length != 1}:\n#{lines.join("\n")}"
        result += "\n... and #{items.length - 10} more" if truncated
        result
      end

      def relative_time(time)
        return "unknown" unless time

        seconds = (Time.now - time).to_i
        case seconds
        when 0..59        then "#{seconds}s ago"
        when 60..3599     then "#{seconds / 60}m ago"
        when 3600..86_399 then "#{seconds / 3600}h ago"
        else "#{seconds / 86_400}d ago"
        end
      end
    end
  end
end
