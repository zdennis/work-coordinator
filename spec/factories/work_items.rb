# frozen_string_literal: true

FactoryBot.define do
  factory :work_item_domain, class: "WorkCoordinator::Domain::WorkItem" do
    id { SecureRandom.uuid }
    title { "Work Item" }
    description { "Description" }
    status { "open" }
    created_at { Time.now }

    initialize_with { WorkCoordinator::Domain::WorkItem.new(**attributes) }
    skip_create
  end
end
