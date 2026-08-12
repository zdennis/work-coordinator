# frozen_string_literal: true

FactoryBot.define do
  factory :work_item_domain, class: "WorkCoordinator::Domain::WorkItem" do
    id { SecureRandom.uuid }
    title { "Work Item" }
    kind { :adhoc }
    external_reference { nil }
    repository { nil }
    workspace_name { nil }
    state { :created }
    phase { nil }
    project_id { nil }
    created_at { Time.now }
    updated_at { Time.now }

    initialize_with { WorkCoordinator::Domain::WorkItem.new(**attributes) }
    skip_create
  end
end
