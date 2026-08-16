# frozen_string_literal: true

require "tempfile"

RSpec.describe WorkCoordinator::Application::WorkItemsStatus do
  subject(:use_case) do
    described_class.new(
      work_item_repo: repo,
      message_sender: sender,
      config: config,
      socket_path: socket_path
    )
  end

  let(:repo)   { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
  let(:config) { WorkCoordinator::Config.new("/tmp/work-coordinator-no-such-config.yml").with_role("home") }
  let(:socket_path) { "/tmp/work-coordinator-does-not-exist.sock" }

  def store(**attrs)
    repo.save(build(:work_item_domain, **attrs))
  end

  it "reports the role and running status in the header" do
    expect(use_case.call.lines.first).to eq("Coordinator  role: home  |  status: not running\n")
  end

  it "falls back to an unknown role when no config is wired" do
    use_case = described_class.new(work_item_repo: repo, message_sender: sender, socket_path: socket_path)
    expect(use_case.call).to include("role: unknown")
  end

  it "says so when there are no work items" do
    expect(use_case.call).to include("No work items found.")
  end

  it "lists a work item's ref, state, phase, and title" do
    store(external_reference: "WC-22", state: :active, phase: "planning", title: "Add status command")
    expect(use_case.call).to include("WC-22", "active", "planning", "Add status command")
  end

  it "falls back to a short id when the item has no external reference" do
    store(id: "abcdef1234-rest", external_reference: nil)
    expect(use_case.call).to include("abcdef12")
  end

  it "truncates titles longer than 50 characters" do
    store(title: "x" * 60)
    expect(use_case.call).to include("#{'x' * 49}…")
  end

  it "filters by state" do
    store(external_reference: "WC-1", state: :active)
    store(external_reference: "WC-2", state: :completed)
    expect(use_case.call(state: :active)).to include("WC-1").and(not_include("WC-2"))
  end

  it "filters by project" do
    store(external_reference: "WC-1", project_id: "p1")
    store(external_reference: "WC-2", project_id: "p2")
    expect(use_case.call(project_id: "p1")).to include("WC-1").and(not_include("WC-2"))
  end

  it "replies to the sender of the inbound message" do
    store(external_reference: "WC-22")
    use_case.call(msg: { from: "+15551234" })
    expect(sender.sent_messages).to contain_exactly(
      hash_including(to: "+15551234", body: a_string_including("WC-22"))
    )
  end

  it "sends nothing when no message is given" do
    use_case.call
    expect(sender.sent_messages).to be_empty
  end

  it "reports the coordinator as running when the socket file exists" do
    Tempfile.create("wc-status-sock") do |file|
      use_case = described_class.new(work_item_repo: repo, message_sender: sender,
                                     config: config, socket_path: file.path)
      expect(use_case.call).to include("status: running")
    end
  end

  def not_include(text)
    satisfy { |body| !body.include?(text) }
  end
end
