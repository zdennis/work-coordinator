# frozen_string_literal: true

FactoryBot.define do
  factory :decision_domain, class: "WorkCoordinator::Domain::Decision" do
    id { SecureRandom.uuid }
    work_item_id { SecureRandom.uuid }
    title { "Use SQLite for local persistence" }
    status { :proposed }
    context { "We need durable storage without a server." }
    decision_text { "Use SQLite." }
    consequences { "Single-writer only." }
    source { "human" }
    created_at { Time.now }

    initialize_with { WorkCoordinator::Domain::Decision.new(**attributes) }
    skip_create
  end
end
