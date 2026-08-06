# frozen_string_literal: true

FactoryBot.define do
  factory :event_domain, class: "WorkCoordinator::Domain::Event" do
    id { SecureRandom.uuid }
    type { "work_item_created" }
    payload { {} }
    occurred_at { Time.now }

    initialize_with { WorkCoordinator::Domain::Event.new(**attributes) }
    skip_create
  end
end
