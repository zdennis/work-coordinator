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

  describe "#last_of_type" do
    it "returns nil when no events of that type exist" do
      store.append(type: "other", work_item_id: "wi-1", source: "system")

      expect(store.last_of_type(type: "missing")).to be_nil
    end

    it "returns the event when exactly one matching event exists" do
      event = store.append(type: "system.notified", work_item_id: "wi-1", source: "system")

      expect(store.last_of_type(type: "system.notified")).to eq(event)
    end

    it "returns the most recently appended matching event when several exist" do
      store.append(type: "system.notified", work_item_id: "wi-1", source: "system", data: { body: "first" })
      last = store.append(type: "system.notified", work_item_id: "wi-1", source: "system", data: { body: "last" })

      expect(store.last_of_type(type: "system.notified")).to eq(last)
    end

    it "scopes to the specified work_item_id when given" do
      store.append(type: "system.notified", work_item_id: "wi-1", source: "system")
      wi2_event = store.append(type: "system.notified", work_item_id: "wi-2", source: "system")

      expect(store.last_of_type(type: "system.notified", work_item_id: "wi-2")).to eq(wi2_event)
    end

    it "returns nil when work_item_id is given but only events for other items exist" do
      store.append(type: "system.notified", work_item_id: "wi-1", source: "system")

      expect(store.last_of_type(type: "system.notified", work_item_id: "wi-99")).to be_nil
    end

    it "returns the newest event across all work items when work_item_id is omitted" do
      store.append(type: "system.notified", work_item_id: "wi-1", source: "system")
      last = store.append(type: "system.notified", work_item_id: "wi-2", source: "system")

      expect(store.last_of_type(type: "system.notified")).to eq(last)
    end
  end
end
