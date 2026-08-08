# frozen_string_literal: true

require "work_coordinator/adapters/socket_message_receiver"

RSpec.describe WorkCoordinator::Adapters::SocketMessageReceiver do
  subject(:receiver) { described_class.new }

  describe "#stop" do
    it "does not raise when called before start" do
      expect { receiver.stop }.not_to raise_error
    end
  end
end
