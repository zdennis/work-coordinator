# frozen_string_literal: true

RSpec.describe WorkCoordinator::Domain::Event do
  describe "construction" do
    it "exposes the attributes it was built with" do
      now = Time.now
      event = build(:event_domain, id: "e-1", work_item_id: "wi-1", type: "work_item.started",
                                   source: "system", data: { phase: :implementing }, occurred_at: now)

      expect(event).to have_attributes(
        id: "e-1", work_item_id: "wi-1", type: "work_item.started", source: "system",
        data: { phase: :implementing }, occurred_at: now
      )
    end

    it "accepts a symbol type" do
      expect(build(:event_domain, type: :"work_item.created").type).to eq(:"work_item.created")
    end

    it "accepts an empty payload" do
      expect(build(:event_domain, data: {}).data).to eq({})
    end

    it "requires every member" do
      expect { described_class.new(id: "e-1", type: "work_item.created") }.to raise_error(ArgumentError)
    end

    it "compares by value" do
      attrs = attributes_for(:event_domain)

      one = described_class.new(**attrs)
      another = described_class.new(**attrs)

      expect(one).to eq(another)
    end

    it "distinguishes events with different payloads" do
      attrs = attributes_for(:event_domain)

      expect(described_class.new(**attrs)).not_to eq(described_class.new(**attrs, data: { a: 1 }))
    end
  end

  describe "#to_h" do
    it "round-trips through the constructor" do
      event = build(:event_domain)

      expect(described_class.new(**event.to_h)).to eq(event)
    end
  end
end
