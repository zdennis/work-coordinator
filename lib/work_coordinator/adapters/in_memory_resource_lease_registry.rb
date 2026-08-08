# frozen_string_literal: true

require_relative "../domain/resource_lease"

module WorkCoordinator
  module Adapters
    # Tracks leases on capacity-limited shared resources in process memory.
    # Resources must be registered before they can be acquired, and released
    # leases are kept for history rather than discarded.
    class InMemoryResourceLeaseRegistry
      def initialize
        @resources = {}
        @leases = {}
      end

      # Declares a resource and how many leases may be held at once. Re-registering
      # an existing name discards its leases.
      #
      # @param name [String]
      # @param capacity [Integer]
      # @return [void]
      def register_resource(name:, capacity: 1)
        @resources[name] = { capacity: capacity }
        @leases[name] = []
      end

      # @param resource_name [String]
      # @param work_item_id [String]
      # @return [Domain::ResourceLease, nil] nil when the resource is at capacity
      # @raise [ArgumentError] when the resource was never registered
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

      # Marks the work item's outstanding leases on the resource as released.
      # Unknown resources and already-released leases are ignored.
      #
      # @param resource_name [String]
      # @param work_item_id [String]
      # @return [void]
      def release(resource_name:, work_item_id:)
        leases = @leases[resource_name] or return
        @leases[resource_name] = leases.map do |lease|
          next lease if lease.work_item_id != work_item_id || lease.released?

          lease.with(released_at: Time.now)
        end
      end

      # @param resource_name [String]
      # @return [String, nil] work item id of the oldest active lease
      def current_holder(resource_name)
        active_leases(resource_name).first&.work_item_id
      end

      # Always empty — this registry does not queue blocked acquirers.
      #
      # @return [Array]
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
