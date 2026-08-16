# frozen_string_literal: true

# Records completion requests instead of touching the repository.
class FakeCompleteWorkItem
  attr_reader :calls

  def initialize
    @calls = []
  end

  def call(work_item_id:, summary:)
    @calls << { work_item_id: work_item_id, summary: summary }
  end
end
