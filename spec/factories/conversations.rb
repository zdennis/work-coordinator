# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_domain, class: "WorkCoordinator::Domain::Conversation" do
    id { SecureRandom.uuid }
    work_item_id { SecureRandom.uuid }
    message_thread_id { nil }
    agent_session { nil }
    last_inbound_at { nil }
    last_outbound_at { nil }

    initialize_with { WorkCoordinator::Domain::Conversation.new(**attributes) }
    skip_create
  end
end
