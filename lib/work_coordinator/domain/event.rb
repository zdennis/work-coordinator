module WorkCoordinator
  module Domain
    Event = Data.define(:id, :type, :payload, :occurred_at)
  end
end
