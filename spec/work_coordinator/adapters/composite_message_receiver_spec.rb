# frozen_string_literal: true

require "work_coordinator/adapters/composite_message_receiver"

RSpec.describe WorkCoordinator::Adapters::CompositeMessageReceiver do
  let(:receiver_class) do
    Class.new do
      attr_reader :started, :stopped

      def initialize(messages = [])
        @messages = messages
        @started = false
        @stopped = false
      end

      def start(&block)
        @started = true
        @messages.each { |message| block.call(message) }
      end

      def stop
        @stopped = true
      end
    end
  end

  # Minimal receiver that delivers messages without tracking started/stopped.
  let(:simple_receiver_class) do
    Class.new do
      def initialize(messages) = @messages = messages
      def stop = nil

      def start(&block)
        @messages.each { |m| block.call(m) }
      end
    end
  end

  def silencing_thread_reports
    previous = Thread.report_on_exception
    Thread.report_on_exception = false
    yield
  ensure
    Thread.report_on_exception = previous
  end

  describe "#start" do
    it "starts each receiver and returns once they have all finished" do
      receivers = [receiver_class.new, receiver_class.new]

      described_class.new(receivers).start { |_| nil }

      expect(receivers.map(&:started)).to eq([true, true])
    end

    it "delivers messages from every receiver to the caller's block" do
      receivers = [receiver_class.new(%w[a b]), receiver_class.new(%w[c])]
      received = []

      described_class.new(receivers).start { |message| received << message }

      expect(received).to match_array(%w[a b c])
    end

    it "processes messages from multiple receivers concurrently" do
      # Each handler blocks until released. Serial dispatch would deadlock here
      # because the second pop would never be reached until the first unblocked.
      latch = Queue.new
      barrier = Queue.new
      received = []
      receivers = [simple_receiver_class.new(%w[a]), simple_receiver_class.new(%w[b])]

      thread = Thread.new do
        described_class.new(receivers).start do |message|
          barrier << message  # signal handler entered
          latch.pop           # wait until both handlers are running
          received << message
        end
      end

      barrier.pop
      barrier.pop
      2.times { latch << :go }
      thread.join

      expect(received).to match_array(%w[a b])
    end

    it "waits for a receiver that blocks until released" do
      latch = Queue.new
      blocking = Class.new do
        define_method(:start) do |&block|
          latch.pop
          block.call("late")
        end
        def stop = nil
      end.new
      received = []

      thread = Thread.new { described_class.new([blocking]).start { |message| received << message } }
      latch << :go
      thread.join

      expect(received).to eq(["late"])
    end

    it "propagates an exception raised by a receiver and stops the others" do
      exploding = Class.new do
        def start(&) = raise("boom")
        def stop = nil
      end.new
      healthy = receiver_class.new

      composite = described_class.new([exploding, healthy])

      expect { silencing_thread_reports { composite.start { |_| nil } } }.to raise_error("boom")
      expect(healthy.stopped).to be(true)
    end
  end

  describe "#stop" do
    it "stops each receiver" do
      receivers = [receiver_class.new, receiver_class.new]

      described_class.new(receivers).stop

      expect(receivers.map(&:stopped)).to eq([true, true])
    end

    it "does not raise when called before start" do
      expect { described_class.new([]).stop }.not_to raise_error
    end
  end
end
