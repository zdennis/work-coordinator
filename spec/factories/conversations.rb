# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_domain, class: "WorkCoordinator::Domain::Conversation" do
    id { SecureRandom.uuid }
    work_item_id { SecureRandom.uuid }
    participant_handles { [] }
    started_at { Time.now }

    initialize_with { WorkCoordinator::Domain::Conversation.new(**attributes) }
    skip_create
  end
end
