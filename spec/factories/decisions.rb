# frozen_string_literal: true

FactoryBot.define do
  factory :decision_domain, class: "WorkCoordinator::Domain::Decision" do
    id { SecureRandom.uuid }
    work_item_id { SecureRandom.uuid }
    description { "A decision" }
    rationale { "Because reasons" }
    decided_at { Time.now }

    initialize_with { WorkCoordinator::Domain::Decision.new(**attributes) }
    skip_create
  end
end
