# frozen_string_literal: true

# Records human informings instead of sending them.
class FakeInformHuman
  attr_reader :calls

  def initialize
    @calls = []
  end

  def call(work_item_id:, body:, work_item:)
    @calls << { work_item_id: work_item_id, body: body, work_item: work_item }
  end
end
