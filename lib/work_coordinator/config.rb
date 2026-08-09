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

    def instruction_context
      data.fetch("instruction_context", "")
    end

    def slash_commands_enabled?
      data.fetch("slash_commands_enabled", true)
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
        # auto_launch_workspace: false
        # workspace_launch_timeout_seconds: 20
        aliases:
          WC: work-coordinator
      YAML
    end
  end
end
