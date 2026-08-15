# frozen_string_literal: true

require "open3"
require "work_coordinator/ports/git_runner"

module WorkCoordinator
  module Adapters
    # Runs git against a checkout by shelling out.
    #
    # The directory defaults to the coordinator's own checkout rather than the
    # process working directory: the daemon may be started from anywhere, and
    # pulling inside the human's project would be destructive.
    class ShellGitRunner
      include Ports::GitRunner

      COORDINATOR_ROOT = File.expand_path("../../..", __dir__)

      # @param dir [String] checkout to operate on
      # @param runner [#call] takes a command string, returns `[stdout, stderr, status]`
      DEFAULT_RUNNER = ->(command) { Open3.capture3(command) }

      def initialize(dir: COORDINATOR_ROOT, runner: DEFAULT_RUNNER)
        @dir = dir
        @runner = runner
      end

      # @return [Boolean]
      def dirty?
        stdout, = run!("git -C #{@dir} status --porcelain")
        !stdout.strip.empty?
      end

      # @raise [Ports::GitRunner::Error] when git exits non-zero
      # @return [void]
      def pull
        _stdout, stderr, status = @runner.call("git -C #{@dir} pull")
        raise Ports::GitRunner::Error, stderr.strip unless status.success?
      end

      # @param sha [String]
      # @return [Integer]
      def commits_since(sha)
        stdout, = run!("git -C #{@dir} rev-list #{sha}..HEAD --count")
        stdout.strip.to_i
      end

      # @return [String]
      def current_sha
        stdout, = run!("git -C #{@dir} rev-parse --short HEAD")
        stdout.strip
      end

      # @return [String, nil]
      def current_tag
        stdout, _stderr, status = @runner.call("git -C #{@dir} describe --tags --exact-match HEAD")
        return nil unless status.success?

        stdout.strip
      end

      private

      def run!(command)
        stdout, stderr, status = @runner.call(command)
        raise Ports::GitRunner::Error, stderr.strip unless status.success?

        [stdout, stderr]
      end
    end
  end
end
