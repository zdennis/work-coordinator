# frozen_string_literal: true

require "fileutils"

module WorkCoordinator
  # Computes default filesystem paths for runtime files (sockets, PID file).
  #
  # The run directory defaults to ~/.local/run/work-coordinator and can be
  # overridden with WC_RUN_DIR. Individual socket paths can be overridden
  # independently with WC_SOCKET and WC_STATUS_SOCKET.
  module Paths
    def self.run_dir
      ENV.fetch("WC_RUN_DIR", File.expand_path("~/.local/run/work-coordinator"))
    end

    def self.socket
      ENV.fetch("WC_SOCKET", File.join(run_dir, "work-coordinator.sock"))
    end

    def self.status_socket
      ENV.fetch("WC_STATUS_SOCKET", File.join(run_dir, "work-coordinator-status.sock"))
    end

    # Creates the run directory if it does not exist. Called once before
    # starting the coordinator so socket files have a stable home outside /tmp.
    def self.ensure_run_dir
      FileUtils.mkdir_p(run_dir)
    end
  end
end
