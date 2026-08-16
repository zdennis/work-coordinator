# frozen_string_literal: true

# Records human notifications instead of sending them.
class FakeNotifyHuman
  attr_reader :calls

  def initialize
    @calls = []
  end

  def call(work_item_id:, body:)
    @calls << { work_item_id: work_item_id, body: body }
  end
end
