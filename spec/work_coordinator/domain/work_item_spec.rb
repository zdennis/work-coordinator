# frozen_string_literal: true

RSpec.describe WorkCoordinator::Domain::WorkItem do
  describe "constants" do
    it "enumerates every state" do
      expect(WorkCoordinator::Domain::WORK_ITEM_STATES).to eq(
        %i[created ready active waiting_for_human waiting_for_resource blocked completed abandoned]
      )
    end

    it "enumerates every kind" do
      expect(WorkCoordinator::Domain::WORK_ITEM_KINDS).to eq(%i[jira chore investigation adhoc])
    end
  end

  describe "phase" do
    it "accepts any free-form string" do
      expect(build(:work_item_domain, phase: "spelunking the auth layer").phase).to eq("spelunking the auth layer")
    end

    it "accepts nil" do
      expect(build(:work_item_domain, phase: nil).phase).to be_nil
    end
  end

  describe "construction" do
    it "exposes the attributes it was built with" do
      now = Time.now
      work_item = build(:work_item_domain, id: "wi-1", title: "Fix login", kind: :jira,
                                           external_reference: "ABC-123", repository: "acme/app",
                                           workspace_name: "acme-abc-123", state: :active,
                                           phase: :implementing, created_at: now, updated_at: now)

      expect(work_item).to have_attributes(
        id: "wi-1", title: "Fix login", kind: :jira, external_reference: "ABC-123",
        repository: "acme/app", workspace_name: "acme-abc-123", state: :active,
        phase: :implementing, created_at: now, updated_at: now
      )
    end

    it "requires every member" do
      expect { described_class.new(id: "wi-1") }.to raise_error(ArgumentError)
    end

    it "defaults project_id to nil when not passed via factory" do
      work_item = build(:work_item_domain)
      expect(work_item.project_id).to be_nil
    end

    it "accepts an explicit project_id" do
      work_item = build(:work_item_domain, project_id: "proj-abc")
      expect(work_item.project_id).to eq("proj-abc")
    end

    it "produces a new instance with updated project_id via with" do
      original = build(:work_item_domain)
      updated  = original.with(project_id: "proj-xyz")
      expect(updated.project_id).to eq("proj-xyz")
      expect(original.project_id).to be_nil
    end

    it "is frozen" do
      expect(build(:work_item_domain)).to be_frozen
    end

    it "compares by value" do
      attrs = attributes_for(:work_item_domain)

      one = described_class.new(**attrs)
      another = described_class.new(**attrs)

      expect(one).to eq(another)
    end
  end

  describe "#with" do
    it "returns a new value with the given members replaced" do
      work_item = build(:work_item_domain, state: :created)

      transitioned = work_item.with(state: :active)

      expect(transitioned.state).to eq(:active)
      expect(transitioned.id).to eq(work_item.id)
    end

    it "leaves the receiver untouched" do
      work_item = build(:work_item_domain, state: :created)

      work_item.with(state: :active)

      expect(work_item.state).to eq(:created)
    end
  end

  describe "#state?" do
    let(:work_item) { build(:work_item_domain, state: :blocked) }

    it "is true for the current state" do
      expect(work_item.state?(:blocked)).to be(true)
    end

    it "is false for any other state" do
      expect(work_item.state?(:active)).to be(false)
    end

    it "is false for a state that does not exist" do
      expect(work_item.state?(:nonsense)).to be(false)
    end
  end

  describe "state predicates" do
    {
      created: :created?,
      ready: :ready?,
      active: :active?,
      waiting_for_human: :waiting_for_human?,
      waiting_for_resource: :waiting_for_resource?,
      blocked: :blocked?,
      completed: :completed?,
      abandoned: :abandoned?
    }.each do |state, predicate|
      it "answers #{predicate} affirmatively in the #{state} state" do
        expect(build(:work_item_domain, state: state).public_send(predicate)).to be(true)
      end

      it "answers #{predicate} negatively in another state" do
        other = state == :created ? :active : :created

        expect(build(:work_item_domain, state: other).public_send(predicate)).to be(false)
      end
    end
  end

  describe "lifecycle aliases" do
    it "treats a created item as open" do
      expect(build(:work_item_domain, state: :created)).to be_open
    end

    it "does not treat a started item as open" do
      expect(build(:work_item_domain, state: :active)).not_to be_open
    end

    it "treats a completed item as done" do
      expect(build(:work_item_domain, state: :completed)).to be_done
    end

    it "does not treat an abandoned item as done" do
      expect(build(:work_item_domain, state: :abandoned)).not_to be_done
    end

    it "treats an active item as in progress" do
      expect(build(:work_item_domain, state: :active)).to be_in_progress
    end

    it "does not treat a blocked item as in progress" do
      expect(build(:work_item_domain, state: :blocked)).not_to be_in_progress
    end
  end

  describe "#terminal?" do
    %i[completed abandoned].each do |state|
      it "is true in the #{state} state" do
        expect(build(:work_item_domain, state: state)).to be_terminal
      end
    end

    %i[created ready active waiting_for_human waiting_for_resource blocked].each do |state|
      it "is false in the #{state} state" do
        expect(build(:work_item_domain, state: state)).not_to be_terminal
      end
    end
  end

  describe "#transition_to" do
    {
      created: %i[ready active abandoned],
      ready: %i[active abandoned],
      active: %i[waiting_for_human waiting_for_resource blocked completed abandoned],
      waiting_for_human: %i[active abandoned],
      waiting_for_resource: %i[active abandoned],
      blocked: %i[active abandoned]
    }.each do |from, targets|
      targets.each do |to|
        it "moves from #{from} to #{to}" do
          work_item = build(:work_item_domain, state: from)

          transitioned = work_item.transition_to(to)

          expect(transitioned.state).to eq(to)
          expect(transitioned.id).to eq(work_item.id)
        end
      end
    end

    it "leaves the receiver untouched" do
      work_item = build(:work_item_domain, state: :created)

      work_item.transition_to(:active)

      expect(work_item.state).to eq(:created)
    end

    it "rejects a move out of a terminal state" do
      work_item = build(:work_item_domain, state: :completed)

      expect { work_item.transition_to(:active) }
        .to raise_error(described_class::InvalidTransition, /completed.*active/)
    end

    it "rejects a move that skips the graph" do
      work_item = build(:work_item_domain, state: :created)

      expect { work_item.transition_to(:completed) }
        .to raise_error(described_class::InvalidTransition, /created.*completed/)
    end

    it "rejects an unknown target state" do
      work_item = build(:work_item_domain, state: :active)

      expect { work_item.transition_to(:nonsense) }.to raise_error(described_class::InvalidTransition)
    end

    it "rejects a self-transition" do
      work_item = build(:work_item_domain, state: :active)

      expect { work_item.transition_to(:active) }.to raise_error(described_class::InvalidTransition)
    end
  end
end
