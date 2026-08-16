# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"

# Test double for a workspace agent listening on a Unix socket. Accepts one
# connection, records the JSON line it receives, and acknowledges.
class FakeWorkspaceAgent
  attr_reader :received_messages

  def initialize(socket_path:)
    @socket_path = socket_path
    @received_messages = []
    @server = nil
    @thread = nil
  end

  def start
    FileUtils.rm_f(@socket_path)
    @server = UNIXServer.new(@socket_path)
    @thread = Thread.new do
      conn = @server.accept
      line = conn.gets&.chomp
      @received_messages << JSON.parse(line) if line
      conn.write("{\"ok\":true}\n")
      conn.close
    rescue IOError, Errno::EBADF, Errno::EPIPE
      # Commands are fire-and-forget, so the client may already be gone.
      nil
    end
  end

  # Blocks until the accept thread has finished handling its one connection.
  def wait_for_message(timeout: 1)
    @thread&.join(timeout)
  end

  def stop
    @server&.close
    @thread&.join(1)
    FileUtils.rm_f(@socket_path)
  end
end
