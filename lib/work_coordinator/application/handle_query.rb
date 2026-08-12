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

      SLASH_USAGE = {
        "build" => "/build WORKSPACE [description]",
        "research" => "/research WORKSPACE [topic]",
        "clear" => "/clear WORKSPACE",
        "test" => "/test WORKSPACE [scope]",
        "fix" => "/fix WORKSPACE [description]",
        "review" => "/review WORKSPACE [scope]",
        "commit" => "/commit WORKSPACE [message]",
        "push" => "/push WORKSPACE",
        "pr" => "/pr WORKSPACE [description]",
        "stop" => "/stop WORKSPACE"
      }.freeze

      # @param work_item_repo [Ports::WorkItemRepository]
      # @param event_store [#recent]
      # @param agent_session [Ports::AgentSession]
      # @param config [WorkCoordinator::Config]
      # @param message_sender [Ports::MessageSender]
      # @param project_repo [Ports::ProjectRepository, nil]
      # @param project_resolver [Application::ProjectResolver, nil]
      # @param set_default_project [Application::SetDefaultProject, nil]
      def initialize(work_item_repo:, event_store:, agent_session:, config:, message_sender:,
                     project_repo: nil, project_resolver: nil, set_default_project: nil)
        @work_item_repo      = work_item_repo
        @event_store         = event_store
        @agent_session       = agent_session
        @config              = config
        @message_sender      = message_sender
        @project_repo        = project_repo
        @project_resolver    = project_resolver
        @set_default_project = set_default_project
      end

      # @param body [String] the message body to match against
      # @return [String, nil] response text, or nil if no query matched
      def call(body:) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize
        case body.strip
        when /\Ahelp\z/i, %r{\A/help\z}i
          help_overview
        when /\Ahelp commands\z/i, %r{\A/help commands\z}i
          help_commands
        when /\Ahelp slash\z/i, %r{\A/help slash\z}i
          help_slash_commands
        when /\Ahelp (.+)\z/i, %r{\A/help (.+)\z}i
          help_command(Regexp.last_match(1).strip)
        when /\Aalias(?:es)?\z/i
          list_aliases
        when /\Aconfig\z/i
          show_config
        when /\Adefault\s+(.+)\z/i
          set_default_project(Regexp.last_match(1).strip)
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
        when %r{\A/(\w+)\z}i
          slash_usage_hint(Regexp.last_match(1).downcase)
        end
      end

      private

      def help_overview # rubocop:disable Metrics/MethodLength
        <<~TEXT.chomp
          ai: queries:
            help [cmd]     usage for a command
            help slash     slash command reference
            aliases        configured aliases
            config         current settings
            status [s|p]   work items by state or project alias
            default P      set P as the default project
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
            /verb  WORKSPACE [args]           slash shorthand (ai: help slash)
        TEXT
      end

      def help_commands
        max_len = COMMAND_DESCRIPTIONS.keys.map(&:length).max
        lines = COMMAND_DESCRIPTIONS.map do |name, desc|
          "  #{name.ljust(max_len)}  #{desc}"
        end
        "CLI commands:\n#{lines.join("\n")}"
      end

      def help_slash_commands # rubocop:disable Metrics/MethodLength
        <<~TEXT.chomp
          ai: slash commands:
            /build    WORKSPACE [description]   "We're building a feature: ..."
            /research WORKSPACE [topic]         "Research ..."
            /clear    WORKSPACE                 send /clear (reset Claude context)
            /test     WORKSPACE [scope]         "Run tests: ..." or "Run the test suite"
            /fix      WORKSPACE [description]   "Fix: ..."
            /review   WORKSPACE [scope]         "Review: ..." or "Review the current changes"
            /commit   WORKSPACE [message]       "Commit: ..." or "Commit the current changes"
            /push     WORKSPACE                 "Push the current branch"
            /pr       WORKSPACE [description]   "Open a pull request: ..." or "Open a pull request"
            /stop     WORKSPACE                 send Ctrl+C (C-c interrupt)
          Examples:
            ai: /build GE add OAuth support
            ai: /test GE
            ai: /stop GE
        TEXT
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
        if @project_repo && (default = @project_repo.default_project)
          items  = @work_item_repo.find_all(project_id: default.id)
          prefix = "[#{default.alias || default.name}] "
        else
          items  = @work_item_repo.find_all
          prefix = ""
        end
        "#{prefix}#{format_work_items(items)}"
      end

      def status_filtered(filter) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        matched_state = Domain::WORK_ITEM_STATES.find do |s|
          s.to_s.downcase.include?(filter.downcase)
        end

        if matched_state
          items = @work_item_repo.find_all(state: matched_state)
          return format_work_items(items)
        end

        # Not a state — only attempt project resolution when both collaborators are present.
        # Without them (backward-compat path), fall through to the existing unknown-state error.
        unless @project_repo && @project_resolver
          known = Domain::WORK_ITEM_STATES.join(", ")
          return "Unknown state: #{filter}. Known states: #{known}"
        end

        resolution = @project_resolver.resolve(filter)

        if resolution.found?
          items = @work_item_repo.find_all(project_id: resolution.project.id)
          "[#{resolution.project.alias || resolution.project.name}] #{format_work_items(items)}"
        elsif resolution.ambiguous?
          names = resolution.candidates.map { |p| p.alias || p.name }.join(", ")
          "Ambiguous: matched #{names}. Be more specific."
        else
          known = Domain::WORK_ITEM_STATES.join(", ")
          "Unknown state or project: #{filter}. Known states: #{known}"
        end
      end

      def shorthand_status(keyword)
        state = SHORTHAND_STATE_MAP.fetch(keyword, keyword.to_sym)
        items = @work_item_repo.find_all(state: state)
        format_work_items(items)
      end

      def set_default_project(query) # rubocop:disable Naming/AccessorMethodName
        return "Project management not configured." unless @set_default_project

        result = @set_default_project.call(query: query)
        result.message
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

      def slash_usage_hint(verb)
        usage = SLASH_USAGE[verb]
        if usage
          "Usage: #{usage}\nSee 'ai: help slash' for all slash commands."
        else
          "Unknown slash command: /#{verb}\nSee 'ai: help slash' for recognized commands."
        end
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
