# frozen_string_literal: true

require_relative "../domain/resource_lease"

module WorkCoordinator
  module Adapters
    class InMemoryResourceLeaseRegistry
      def initialize
        @resources = {}
        @leases = {}
      end

      def register_resource(name:, capacity: 1)
        @resources[name] = { capacity: capacity }
        @leases[name] = []
      end

      def acquire(resource_name:, work_item_id:)
        resource = @resources[resource_name] or raise ArgumentError, "Unknown resource: #{resource_name}"
        active = active_leases(resource_name)
        return nil if active.size >= resource[:capacity]

        lease = Domain::ResourceLease.new(
          id: "#{resource_name}-#{work_item_id}-#{Time.now.to_f}",
          resource_name: resource_name,
          work_item_id: work_item_id,
          acquired_at: Time.now,
          released_at: nil
        )
        @leases[resource_name] << lease
        lease
      end

      def release(resource_name:, work_item_id:)
        leases = @leases[resource_name] or return
        @leases[resource_name] = leases.map do |lease|
          next lease if lease.work_item_id != work_item_id || lease.released?

          lease.with(released_at: Time.now)
        end
      end

      def current_holder(resource_name)
        active_leases(resource_name).first&.work_item_id
      end

      def waiting(_resource_name)
        []
      end

      private

      def active_leases(resource_name)
        (@leases[resource_name] || []).reject(&:released?)
      end
    end
  end
end
