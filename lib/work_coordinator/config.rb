# frozen_string_literal: true

require "fileutils"
require "yaml"

module WorkCoordinator
  class Config
    DEFAULT_AI_COMMAND = "claude -p"

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

    # An untargeted message (no role token) is only for the default role;
    # a targeted one matches the role itself or any of its aliases.
    def matches_role?(role_token)
      mine = role.to_s.downcase
      return mine.empty? || mine == "default" if role_token.nil?

      token = role_token.to_s.downcase
      token == mine || role_aliases.map { |a| a.to_s.downcase }.include?(token)
    end

    def instruction_context
      data.fetch("instruction_context", "")
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
        # auto_launch_workspace: false  # Automatically launch dormant workspaces when routing AI commands via URL
        # workspace_launch_timeout_seconds: 20  # Max seconds to wait for a launched workspace to become active
        aliases:
          WC: work-coordinator
      YAML
    end
  end
end
