# frozen_string_literal: true

RSpec.describe WorkCoordinator::Adapters::ConsoleAiCommandHandler do
  let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }

  def handler(handle_query:, dispatch: nil)
    described_class.new(handle_query: handle_query, dispatch_ai_command: dispatch, message_sender: message_sender)
  end

  def query_returning(response)
    Class.new do
      define_method(:call) { |**| response }
    end.new
  end

  def dispatcher_returning(result)
    Class.new do
      attr_reader :bodies

      define_method(:initialize) { @bodies = [] }
      define_method(:call) do |body:|
        @bodies << body
        result
      end
    end.new
  end

  it "answers a query without dispatching" do
    dispatch = dispatcher_returning(nil)
    subject = handler(handle_query: query_returning("42 items"), dispatch: dispatch)

    expect { subject.call(work_item_ref: "WC-1", body: "status") }.to output(/Query handled/).to_stdout

    expect(message_sender.sent_messages.map { |m| m[:body] }).to eq(["42 items"])
    expect(dispatch.bodies).to be_empty
  end

  it "dispatches when no query matches" do
    result = Struct.new(:dispatched, :project, :summary, :failure_reason).new(true, "web", "did the thing", nil)
    dispatch = dispatcher_returning(result)
    subject = handler(handle_query: query_returning(nil), dispatch: dispatch)

    expect { subject.call(work_item_ref: "WC-1", body: "fix login") }.to output(/dispatched to 'web'/).to_stdout

    expect(dispatch.bodies).to eq(["WC-1 fix login"])
  end

  it "reports an unmatched dispatch" do
    result = Struct.new(:dispatched, :project, :summary, :failure_reason).new(false, nil, nil, "no alias")
    subject = handler(handle_query: query_returning(nil), dispatch: dispatcher_returning(result))

    expect { subject.call(work_item_ref: nil, body: "hello") }.to output(/unmatched \(no alias\)/).to_stdout
  end

  it "warns instead of raising when the handler blows up" do
    exploding = Class.new do
      def call(**)
        raise "boom"
      end
    end.new
    subject = handler(handle_query: exploding)

    expect { subject.call(work_item_ref: nil, body: "hi") }.to output(/Error dispatching AI command: boom/).to_stderr
  end
end
