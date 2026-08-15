# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples "a restart state repository" do
  describe "#load" do
    it "returns nil when nothing is stored" do
      expect(repo.load).to be_nil
    end

    it "returns the saved state" do
      repo.save(attempt: 2)

      expect(repo.load.attempt).to eq(2)
    end
  end

  describe "#save" do
    it "returns the saved state" do
      expect(repo.save(attempt: 1).attempt).to eq(1)
    end

    it "overwrites the previous state rather than adding another" do
      repo.save(attempt: 1)
      repo.save(attempt: 3)

      expect(repo.load.attempt).to eq(3)
    end
  end

  describe "#clear" do
    it "removes the stored state" do
      repo.save(attempt: 1)
      repo.clear

      expect(repo.load).to be_nil
    end

    it "is a no-op when nothing is stored" do
      expect { repo.clear }.not_to raise_error
      expect(repo.load).to be_nil
    end
  end
end

RSpec.describe WorkCoordinator::Adapters::SqliteRestartStateRepository do
  subject(:repo) { described_class.new }

  it_behaves_like "a restart state repository"

  it "keeps a single row across repeated saves" do
    repo.save(attempt: 1)
    repo.save(attempt: 2)

    expect(WorkCoordinator::Persistence::Models::RestartStateRecord.count).to eq(1)
  end

  it "keys the row with the fixed singleton id" do
    repo.save(attempt: 1)

    expect(WorkCoordinator::Persistence::Models::RestartStateRecord.first.id).to eq("coordinator")
  end

  it "is idempotent under repeated migration" do
    expect { WorkCoordinator::Persistence.migrate! }.not_to raise_error
    expect { repo.save(attempt: 1) }.not_to raise_error
  end

  # The fake stands in for this adapter everywhere else, so it has to honour
  # the same contract.
  describe WorkCoordinator::Adapters::InMemoryRestartStateRepository do
    subject(:repo) { described_class.new }

    it_behaves_like "a restart state repository"
  end
end
