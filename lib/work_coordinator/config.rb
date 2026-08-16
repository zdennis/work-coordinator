# frozen_string_literal: true

require "fileutils"
require "yaml"

module WorkCoordinator
  class Config
    DEFAULT_AI_COMMAND = "claude -p"
    DEFAULT_STATUS_REPORTING_TEMPLATE = <<~TEMPLATE
      <work_coordinator>
      You are working on %{work_item_ref} in workspace %{workspace}. Report progress by running
      the commands below. Reports are best-effort — if the coordinator is unreachable they exit 0
      silently, so always run them.

      <reporting_commands>
      Meaningful milestone (step done, discovery made, new phase started):
        %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type status_update --message "<one line>"

      Phase transition (e.g. planning → implementing → testing):
        %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type phase_change --phase "<phase>"

      Blocked waiting on another agent or external resource:
        %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type status_update --message "waiting: <what>"

      Question requiring a human decision before you can proceed:
        %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type error --message "question: <your question>"

      Cannot proceed due to an error or hard blocker:
        %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type error --message "<reason>"

      Work fully complete — REQUIRED, run this even for trivial tasks:
      %{task_complete_line}
      </reporting_commands>

      <artifacts>
      If the work produced an artifact — audit, report, analysis, recommendation, summary, or any
      deliverable meant to be read — create a private GitHub gist in Markdown and include the URL
      in your status_update or task_complete message. The message body may include additional lines
      for artifact links after the one-line summary.

      Example:
        %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type status_update \\
          --message "analysis complete
      gist: https://gist.github.com/..."

      Rules for gists:
      - Private only (secret gist, not public).
      - Markdown format.
      - No secrets, credentials, tokens, PII, or any sensitive information — describe findings
        without including the raw sensitive data.
      </artifacts>

      <rules>
      - Your last action when work is done must be running the task_complete command. This is mandatory — no exceptions, no matter how trivial the task.
      - Report at every meaningful transition. Do not go silent for long stretches.
      - First line of every message is a one-line summary. Additional lines may carry artifact links.
      - Do not report task_complete more than once.
      </rules>
      </work_coordinator>
    TEMPLATE

    def self.config_dir
      xdg = ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config"))
      File.join(xdg, "work-coordinator")
    end

    def self.default_config_path
      File.join(config_dir, "config.yml")
    end

    def self.load(path: nil)
      resolved = path ||
                 ENV.fetch("WC_CONFIG", nil) ||
                 default_config_path
      new(resolved)
    end

    attr_reader :path

    def initialize(path = self.class.default_config_path)
      @path = path
    end

    def ai_command
      data.fetch("ai_command", DEFAULT_AI_COMMAND)
    end

    def aliases
      data.fetch("aliases", {})
    end

    def role
      @role_override || data.fetch("role", "default")
    end

    # Other names this coordinator answers to, in addition to its role.
    def role_aliases
      Array(data.fetch("role_aliases", []))
    end

    # Returns a copy of this config whose role is overridden, leaving the
    # file-backed config untouched.
    def with_role(role)
      copy = dup
      copy.role_override = role
      copy
    end

    # Role assumed for messages that carry no role token.
    # Defaults to "default" so existing senders continue to work on
    # unconfigured machines.
    def default_message_role
      data.fetch("default_message_role", "default")
    end

    # An untargeted message (no role token) is treated as carrying
    # `default_message_role`; a targeted one matches the coordinator's role
    # or any of its aliases.
    def matches_role?(role_token)
      effective_token = role_token.nil? ? default_message_role : role_token
      token = effective_token.to_s.downcase
      mine  = role.to_s.downcase
      token == mine || role_aliases.map { |a| a.to_s.downcase }.include?(token)
    end

    def instruction_context
      data.fetch("instruction_context", "")
    end

    DEFAULT_STATUS_REPORTING_CLI = "work-coordinator"

    # Template rendered into the `reporting_instructions` field of a `command`
    # payload. Falls back to DEFAULT_STATUS_REPORTING_TEMPLATE when unset.
    def status_reporting_template
      data.fetch("status_reporting_template", DEFAULT_STATUS_REPORTING_TEMPLATE)
    end

    # Returns true only when the key is explicitly present in the config file.
    def status_reporting_template?
      data.key?("status_reporting_template")
    end

    def write_status_reporting_template(template)
      new_data = data.dup
      new_data["status_reporting_template"] = template
      write_data!(new_data)
    end

    # Base CLI invocation substituted as %{cli_command}. Configurable because a
    # checkout runs `bin/work-coordinator`, not the installed binary.
    def status_reporting_cli
      data.fetch("status_reporting_cli", DEFAULT_STATUS_REPORTING_CLI)
    end

    def slash_commands_enabled?
      data.fetch("slash_commands_enabled", true)
    end

    def tmux_fallback_enabled?
      data.fetch("tmux_fallback_enabled", true)
    end

    def dispatch_via_sockets?
      data.fetch("dispatch_via_sockets", true)
    end

    def implicit_reply_enabled?
      data.fetch("implicit_reply_enabled", true)
    end

    def auto_launch_workspace
      data.fetch("auto_launch_workspace", false)
    end

    def workspace_launch_timeout_seconds
      data.fetch("workspace_launch_timeout_seconds", 20)
    end

    def resolve_alias(keyword)
      return nil if keyword.nil? || keyword.empty?

      aliases[keyword.strip.upcase]
    end

    def exist?
      File.exist?(@path)
    end

    def write_defaults!
      return if exist?

      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, default_content)
    end

    def set_alias(short, project)
      new_data = data.dup
      new_data["aliases"] = (new_data["aliases"] || {}).dup
      new_data["aliases"][short] = project
      write_data!(new_data)
    end

    def remove_alias(short)
      new_data = data.dup
      new_data["aliases"] = (new_data["aliases"] || {}).dup
      removed = new_data["aliases"].delete(short)
      write_data!(new_data)
      removed
    end

    protected

    attr_writer :role_override

    private

    def data
      @data ||= exist? ? (YAML.safe_load_file(@path) || {}) : {}
    end

    def write_data!(new_data)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, "# work-coordinator configuration\n#{YAML.dump(new_data).sub(/\A---\n/, '')}")
      @data = nil
    end

    def default_content
      <<~YAML
        # work-coordinator configuration
        ai_command: "#{DEFAULT_AI_COMMAND}"
        slash_commands_enabled: true
        # tmux_fallback_enabled: true  # Fall back to tmux delivery when a workspace agent's socket is gone
        # dispatch_via_sockets: true   # Steer registered workspace agents via their socket instead of tmux
        # implicit_reply_enabled: true # Allow bare `reply: …` to route to the single waiting item
        # role: default                # Role token this coordinator answers to
        # role_aliases: []             # Extra names this coordinator also answers to
        # default_message_role: default  # Role assumed for messages with no role token
        # auto_launch_workspace: false  # Automatically launch dormant workspaces when routing AI commands via URL
        # workspace_launch_timeout_seconds: 20  # Max seconds to wait for a launched workspace to become active
        # status_reporting_cli: work-coordinator  # Base CLI invocation used in status reporting instructions
        status_reporting_template: |
        #{DEFAULT_STATUS_REPORTING_TEMPLATE.gsub(/^/, '  ').rstrip}
        aliases:
          WC: work-coordinator
      YAML
    end
  end
end
