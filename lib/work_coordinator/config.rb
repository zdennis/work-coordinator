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

    def exist?
      File.exist?(@path)
    end

    def write_defaults!
      return if exist?

      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, default_content)
    end

    private

    def data
      @data ||= exist? ? (YAML.safe_load_file(@path) || {}) : {}
    end

    def default_content
      <<~YAML
        # work-coordinator configuration
        ai_command: "#{DEFAULT_AI_COMMAND}"
      YAML
    end
  end
end
