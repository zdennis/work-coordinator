# frozen_string_literal: true

RSpec.describe WorkCoordinator::Application::InMemoryEventStore do
  subject(:store) { described_class.new }

  describe "#append" do
    it "returns the appended event" do
      event = store.append(type: "work_item.created", work_item_id: "wi-1", source: "system")

      expect(event).to have_attributes(type: "work_item.created", work_item_id: "wi-1", source: "system")
    end

    it "defaults the payload to empty" do
      expect(store.append(type: "x", work_item_id: "wi-1", source: "system").data).to eq({})
    end

    it "keeps the payload it is given" do
      event = store.append(type: "x", work_item_id: "wi-1", source: "system", data: { a: 1 })

      expect(event.data).to eq({ a: 1 })
    end

    it "defaults occurred_at to now" do
      before = Time.now
      event = store.append(type: "x", work_item_id: "wi-1", source: "system")

      expect(event.occurred_at).to be_between(before, Time.now)
    end

    it "keeps an explicit occurred_at" do
      past = Time.now - 3600

      expect(store.append(type: "x", work_item_id: "wi-1", source: "system", occurred_at: past).occurred_at)
        .to eq(past)
    end

    it "numbers ids sequentially from one" do
      ids = 3.times.map { store.append(type: "x", work_item_id: "wi-1", source: "system").id }

      expect(ids).to eq(%w[1 2 3])
    end

    it "numbers independently per store instance" do
      store.append(type: "x", work_item_id: "wi-1", source: "system")

      expect(described_class.new.append(type: "x", work_item_id: "wi-1", source: "system").id).to eq("1")
    end
  end

  describe "#all" do
    it "is empty for a fresh store" do
      expect(store.all).to be_empty
    end

    it "returns events in append order" do
      store.append(type: "first", work_item_id: "wi-1", source: "system")
      store.append(type: "second", work_item_id: "wi-1", source: "system")

      expect(store.all.map(&:type)).to eq(%w[first second])
    end

    it "returns events for every work item, not just one" do
      store.append(type: "x", work_item_id: "wi-1", source: "system")
      store.append(type: "x", work_item_id: "wi-2", source: "system")

      expect(store.all.map(&:work_item_id)).to eq(%w[wi-1 wi-2])
    end

    it "hands back a copy the caller cannot use to corrupt the store" do
      store.append(type: "x", work_item_id: "wi-1", source: "system")

      store.all.clear

      expect(store.all.size).to eq(1)
    end
  end
end
