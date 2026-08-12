# frozen_string_literal: true

FactoryBot.define do
  factory :project_domain, class: "WorkCoordinator::Domain::Project" do
    sequence(:id)   { |n| "project-id-#{n}" }
    sequence(:name) { |n| "project-#{n}" }
    # `alias` is a Ruby keyword — use alias_attr here and pass it explicitly
    # in initialize_with so FactoryBot does not trip on the reserved word.
    alias_attr     { nil }
    workspace_name { nil }
    is_default     { false }
    created_at     { Time.now }
    updated_at     { Time.now }

    initialize_with do
      WorkCoordinator::Domain::Project.new(
        id: id,
        name: name,
        alias: alias_attr,
        workspace_name: workspace_name,
        is_default: is_default,
        created_at: created_at,
        updated_at: updated_at
      )
    end
    skip_create

    trait :default do
      is_default { true }
    end

    trait :with_alias do
      alias_attr { name.upcase.split("-").first(2).join }
    end
  end
end
