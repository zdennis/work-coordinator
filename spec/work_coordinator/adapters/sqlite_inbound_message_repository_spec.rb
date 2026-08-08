# frozen_string_literal: true

require "work_coordinator/adapters/sqlite_inbound_message_repository"

RSpec.describe WorkCoordinator::Adapters::SqliteInboundMessageRepository do
  subject(:repository) { described_class.new }

  describe "#seen?" do
    it "returns false for an unknown guid" do
      expect(repository.seen?("unknown-guid")).to be(false)
    end

    it "returns true after the guid has been recorded" do
      repository.record("known-guid")

      expect(repository.seen?("known-guid")).to be(true)
    end
  end

  describe "#record" do
    it "is idempotent for the same guid" do
      repository.record("dupe-guid")

      expect { repository.record("dupe-guid") }.not_to raise_error
    end
  end
end
