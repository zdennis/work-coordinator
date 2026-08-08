# frozen_string_literal: true

RSpec.describe WorkCoordinator::Domain::Decision do
  describe "construction" do
    it "exposes the attributes it was built with" do
      now = Time.now
      decision = build(:decision_domain, id: "d-1", work_item_id: "wi-1", title: "Use SQLite",
                                         status: :accepted, context: "No server available",
                                         decision_text: "Ship SQLite", consequences: "Single writer",
                                         source: "human", created_at: now)

      expect(decision).to have_attributes(
        id: "d-1", work_item_id: "wi-1", title: "Use SQLite", status: :accepted,
        context: "No server available", decision_text: "Ship SQLite",
        consequences: "Single writer", source: "human", created_at: now
      )
    end

    it "allows the narrative fields to be omitted" do
      decision = build(:decision_domain, context: nil, decision_text: nil, consequences: nil)

      expect(decision).to have_attributes(context: nil, decision_text: nil, consequences: nil)
    end

    it "requires every member" do
      expect { described_class.new(id: "d-1", title: "Partial") }.to raise_error(ArgumentError)
    end

    it "compares by value" do
      attrs = attributes_for(:decision_domain)

      one = described_class.new(**attrs)
      another = described_class.new(**attrs)

      expect(one).to eq(another)
    end
  end

  describe "status predicates" do
    { proposed: :proposed?, accepted: :accepted?, superseded: :superseded?, rejected: :rejected? }
      .each do |status, predicate|
      it "answers #{predicate} affirmatively when #{status}" do
        expect(build(:decision_domain, status: status).public_send(predicate)).to be(true)
      end

      it "answers #{predicate} negatively for another status" do
        other = status == :accepted ? :rejected : :accepted

        expect(build(:decision_domain, status: other).public_send(predicate)).to be(false)
      end
    end

    it "reports no status when the status is unrecognized" do
      decision = build(:decision_domain, status: :draft)

      expect([decision.proposed?, decision.accepted?, decision.superseded?, decision.rejected?]).to all(be(false))
    end
  end

  describe "#with" do
    it "supersedes without mutating the original" do
      decision = build(:decision_domain, status: :accepted)

      superseded = decision.with(status: :superseded)

      expect(superseded).to be_superseded
      expect(decision).to be_accepted
    end
  end
end
