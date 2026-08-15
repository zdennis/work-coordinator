# frozen_string_literal: true

require "spec_helper"
require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_agent_session"
require "work_coordinator/adapters/fake_message_sender"
require "work_coordinator/application/handle_query"
require "work_coordinator/application/event_store"

RSpec.describe WorkCoordinator::Application::HandleQuery do
  subject(:use_case) do
    described_class.new(
      work_item_repo: repo,
      event_store: event_store,
      agent_session: agent_session,
      config: config,
      message_sender: message_sender
    )
  end

  let(:repo)           { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:event_store)    { WorkCoordinator::Application::InMemoryEventStore.new }
  let(:agent_session)  { WorkCoordinator::Adapters::FakeAgentSession.new }
  let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
  let(:config)         { instance_double(WorkCoordinator::Config, aliases: {}, path: "~/.config/work-coordinator/config.yml") }

  def call(body)
    use_case.call(body: body)
  end

  # -------------------------------------------------------------------------
  # help
  # -------------------------------------------------------------------------

  describe "help" do
    it "returns the help overview", :aggregate_failures do
      result = call("help")
      expect(result).to include("ai: queries:")
      expect(result).to include("ai: actions:")
      expect(result).to include("help [cmd]")
      expect(result).to include("status [s|p]")
      expect(result).to include("help slash")
      expect(result).to include("/verb")
    end

    it "matches case-insensitively (HELP)" do
      result = call("HELP")
      expect(result).to include("ai: queries:")
    end

    it "matches /help slash command syntax" do
      result = call("/help")
      expect(result).to include("ai: queries:")
    end

    it "matches /help slash syntax case-insensitively" do
      result = call("/HELP")
      expect(result).to include("ai: queries:")
    end
  end

  # -------------------------------------------------------------------------
  # help commands
  # -------------------------------------------------------------------------

  # -------------------------------------------------------------------------
  # help slash
  # -------------------------------------------------------------------------

  describe "help slash" do
    it "returns the slash command reference", :aggregate_failures do
      result = call("help slash")
      expect(result).to include("ai: slash commands:")
      expect(result).to include("/build")
      expect(result).to include("/research")
      expect(result).to include("/clear")
      expect(result).to include("/test")
      expect(result).to include("/fix")
      expect(result).to include("/review")
      expect(result).to include("/commit")
      expect(result).to include("/push")
      expect(result).to include("/pr")
      expect(result).to include("/stop")
      expect(result).to include("/restart")
      expect(result).to include("/update")
    end

    it "notes that restart and update take no workspace argument", :aggregate_failures do
      result = call("help slash")
      expect(result).to match(%r{/restart\s+restart the coordinator \(no WORKSPACE\)})
      expect(result).to match(%r{/update\s+pull latest code, then restart \(no WORKSPACE\)})
    end

    it "returns a usage line for 'help restart'", :aggregate_failures do
      result = call("help restart")
      expect(result).to include("Usage: /restart")
      expect(result).not_to include("Unknown command:")
    end

    it "returns a usage line for 'help update'", :aggregate_failures do
      result = call("help update")
      expect(result).to include("Usage: /update")
      expect(result).not_to include("Unknown command:")
    end

    it "also matches /help slash syntax" do
      result = call("/help slash")
      expect(result).to include("ai: slash commands:")
    end

    it "matches case-insensitively (HELP SLASH)" do
      result = call("HELP SLASH")
      expect(result).to include("ai: slash commands:")
    end

    it "does not fall through to the generic help_command unknown message" do
      result = call("help slash")
      expect(result).not_to include("Unknown command:")
    end
  end

  describe "help commands" do
    it "returns the list of CLI commands" do
      result = call("help commands")
      expect(result).to include("CLI commands:")
      expect(result).to include("init")
      expect(result).to include("create config file")
      expect(result).to include("status")
      expect(result).to include("list all work items")
    end
  end

  # -------------------------------------------------------------------------
  # help <name>
  # -------------------------------------------------------------------------

  describe "help <name>" do
    it "fuzzy-matches a command name and returns its help" do
      result = call("help status")
      expect(result).to include("status: list all work items")
      expect(result).to include("work-coordinator status --help")
    end

    it "returns an unknown command message when no match is found" do
      result = call("help unknown-xyz")
      expect(result).to include("Unknown command: unknown-xyz")
      expect(result).to include("help commands")
    end
  end

  # -------------------------------------------------------------------------
  # aliases
  # -------------------------------------------------------------------------

  describe "aliases" do
    context "when aliases are configured" do
      let(:config) do
        instance_double(WorkCoordinator::Config,
                        aliases: { "MS" => "my-service", "BI" => "acme-billing" },
                        path: "~/.config/work-coordinator/config.yml")
      end

      it "returns the formatted alias list" do
        result = call("aliases")
        expect(result).to include("Aliases (2):")
        expect(result).to include("MS -> my-service")
        expect(result).to include("BI -> acme-billing")
      end
    end

    context "when no aliases are configured" do
      it "returns the no-aliases message" do
        result = call("aliases")
        expect(result).to include("No aliases configured")
        expect(result).to include("work-coordinator alias add")
      end
    end

    it "also matches 'alias'" do
      result = call("alias")
      expect(result).to include("No aliases configured")
    end
  end

  # -------------------------------------------------------------------------
  # config
  # -------------------------------------------------------------------------

  describe "config" do
    let(:config) do
      instance_double(WorkCoordinator::Config,
                      aliases: { "MS" => "my-service" },
                      path: "~/.config/work-coordinator/config.yml")
    end

    it "returns the config summary" do
      result = call("config")
      expect(result).to include("Config:")
      expect(result).to include("aliases: 1 configured")
    end
  end

  # -------------------------------------------------------------------------
  # status
  # -------------------------------------------------------------------------

  describe "status" do
    context "with no work items" do
      it "returns an appropriate message" do
        result = call("status")
        expect(result).to include("No work items.")
      end
    end

    context "with work items" do
      before do
        repo.save(build(:work_item_domain,
                        external_reference: "MS-123",
                        title: "Fix login timeout",
                        state: :active,
                        phase: :implementing))
        repo.save(build(:work_item_domain,
                        external_reference: "MS-456",
                        title: "Add OAuth support",
                        state: :waiting_for_human,
                        phase: nil))
      end

      it "returns the formatted list", :aggregate_failures do
        result = call("status")
        expect(result).to include("2 work items:")
        expect(result).to include("MS-123")
        expect(result).to include("active/implementing")
        expect(result).to include("Fix login timeout")
        expect(result).to include("MS-456")
        expect(result).to include("waiting_for_human")
      end
    end
  end

  # -------------------------------------------------------------------------
  # status <filter>
  # -------------------------------------------------------------------------

  describe "status <filter>" do
    before do
      repo.save(build(:work_item_domain,
                      external_reference: "MS-100",
                      title: "Active task",
                      state: :active))
      repo.save(build(:work_item_domain,
                      external_reference: "MS-200",
                      title: "Blocked task",
                      state: :blocked))
    end

    it "filters to active items" do
      result = call("status active")
      expect(result).to include("MS-100")
      expect(result).not_to include("MS-200")
    end

    it "fuzzy-matches 'bloc' to blocked" do
      result = call("status bloc")
      expect(result).to include("MS-200")
      expect(result).not_to include("MS-100")
    end

    it "returns an unknown state message for unrecognized filters" do
      result = call("status unknown-state")
      expect(result).to include("Unknown state: unknown-state")
      expect(result).to include("Known states:")
    end
  end

  # -------------------------------------------------------------------------
  # shorthand status queries
  # -------------------------------------------------------------------------

  describe "shorthand status" do
    before do
      repo.save(build(:work_item_domain,
                      external_reference: "MS-300",
                      title: "Blocked item",
                      state: :blocked))
      repo.save(build(:work_item_domain,
                      external_reference: "MS-400",
                      title: "Waiting item",
                      state: :waiting_for_human))
    end

    it "'blocked' shorthand filters to blocked items" do
      result = call("blocked")
      expect(result).to include("MS-300")
      expect(result).not_to include("MS-400")
    end

    it "'waiting' maps to waiting_for_human" do
      result = call("waiting")
      expect(result).to include("MS-400")
      expect(result).not_to include("MS-300")
    end
  end

  # -------------------------------------------------------------------------
  # item <ref>
  # -------------------------------------------------------------------------

  describe "item <ref>" do
    context "when the item exists" do
      before do
        repo.save(build(:work_item_domain,
                        external_reference: "MS-123",
                        title: "Fix login timeout",
                        state: :active,
                        phase: :implementing,
                        kind: :jira,
                        repository: "acme-billing",
                        workspace_name: "work:claude.0",
                        updated_at: Time.now - (47 * 60)))
      end

      it "returns item detail", :aggregate_failures do
        result = call("item MS-123")
        expect(result).to include("MS-123: Fix login timeout")
        expect(result).to include("state: active")
        expect(result).to include("phase: implementing")
        expect(result).to include("repo: acme-billing")
        expect(result).to include("pane: work:claude.0")
        expect(result).to include("updated:")
      end

      it "matches case-insensitively (lowercase ref)" do
        result = call("item ms-123")
        expect(result).to include("MS-123: Fix login timeout")
      end
    end

    context "when the item does not exist" do
      it "returns a not-found message" do
        result = call("item MS-999")
        expect(result).to include("No work item with ref: MS-999")
      end
    end
  end

  # -------------------------------------------------------------------------
  # recent
  # -------------------------------------------------------------------------

  describe "recent" do
    context "with no events" do
      it "returns a no-events message" do
        result = call("recent")
        expect(result).to include("No events recorded yet.")
      end
    end

    context "with events" do
      before do
        5.times do |i|
          event_store.append(
            type: :"human.replied",
            work_item_id: "MS-#{i + 1}",
            source: "coordinator",
            occurred_at: Time.now - (i * 60)
          )
        end
        # Add a 6th event
        event_store.append(
          type: :"system.notified",
          work_item_id: "MS-99",
          source: "coordinator",
          occurred_at: Time.now - 3600
        )
      end

      it "returns the last 5 events by default" do
        result = call("recent")
        expect(result).to include("Recent events (5):")
        expect(result).to include("human.replied")
      end

      it "respects a custom limit" do
        result = call("recent 10")
        expect(result).to include("Recent events (6):")
      end
    end
  end

  # -------------------------------------------------------------------------
  # panes
  # -------------------------------------------------------------------------

  describe "panes" do
    context "with active panes" do
      before do
        repo.save(build(:work_item_domain,
                        external_reference: "MS-123",
                        state: :active,
                        workspace_name: "work:claude.0"))
        agent_session.stub_panes(["work:claude.0", "billing:dev.1"])
      end

      it "returns the formatted pane list with work item correlation" do
        result = call("panes")
        expect(result).to include("Active panes:")
        expect(result).to include("work:claude.0")
        expect(result).to include("MS-123")
        expect(result).to include("billing:dev.1")
        expect(result).to include("(unregistered)")
      end
    end

    context "with no panes" do
      it "returns a no-panes message" do
        result = call("panes")
        expect(result).to include("No active tmux panes.")
      end
    end
  end

  # -------------------------------------------------------------------------
  # nil return for non-matching bodies
  # -------------------------------------------------------------------------

  describe "non-matching body" do
    it "returns nil for something that looks like an AI action" do
      expect(call("claude acme-billing fix the timeout")).to be_nil
    end

    it "returns nil for arbitrary text" do
      expect(call("some workspace instructions")).to be_nil
    end

    it "returns nil for empty-ish strings" do
      expect(call("   ")).to be_nil
    end
  end

  # -------------------------------------------------------------------------
  # bare slash commands (no workspace)
  # -------------------------------------------------------------------------

  describe "bare slash commands" do
    it "returns a usage hint for /build" do
      result = call("/build")
      expect(result).to include("Usage: /build WORKSPACE [description]")
      expect(result).to include("ai: help slash")
    end

    it "returns a usage hint for /test" do
      result = call("/test")
      expect(result).to include("Usage: /test WORKSPACE [scope]")
      expect(result).to include("ai: help slash")
    end

    it "returns a usage hint for /stop" do
      result = call("/stop")
      expect(result).to include("Usage: /stop WORKSPACE")
      expect(result).to include("ai: help slash")
    end

    it "matches case-insensitively (/BUILD)" do
      result = call("/BUILD")
      expect(result).to include("Usage: /build WORKSPACE [description]")
    end

    it "returns an unknown slash command message for /foo" do
      result = call("/foo")
      expect(result).to include("Unknown slash command: /foo")
      expect(result).to include("ai: help slash")
    end

    it "does not intercept /help (regression guard)" do
      result = call("/help")
      expect(result).to include("ai: queries:")
      expect(result).not_to include("Unknown slash command")
    end

    it "returns nil for /stop MS (with workspace) so dispatch still handles it" do
      expect(call("/stop MS")).to be_nil
    end
  end

  # -------------------------------------------------------------------------
  # Project-aware helpers
  # -------------------------------------------------------------------------

  def build_project_use_case(project_repo:)
    resolver         = WorkCoordinator::Application::ProjectResolver.new(project_repo: project_repo)
    set_default_proj = WorkCoordinator::Application::SetDefaultProject.new(
      project_repo: project_repo,
      project_resolver: resolver
    )
    described_class.new(
      work_item_repo: repo,
      event_store: event_store,
      agent_session: agent_session,
      config: config,
      message_sender: message_sender,
      project_repo: project_repo,
      project_resolver: resolver,
      set_default_project: set_default_proj
    )
  end

  # -------------------------------------------------------------------------
  # ai: default PROJECT
  # -------------------------------------------------------------------------

  describe "default PROJECT" do
    let(:project_repo) { WorkCoordinator::Adapters::InMemoryProjectRepository.new }
    let(:uc)           { build_project_use_case(project_repo: project_repo) }

    context "when the project is found" do
      before do
        project_repo.save(build(:project_domain, name: "my-service", alias_attr: "MS"))
      end

      it "returns the success message" do
        result = uc.call(body: "default MS")
        expect(result).to include("Default project set to")
      end
    end

    context "when the project is not found" do
      it "returns a not-found message" do
        result = uc.call(body: "default nonexistent")
        expect(result).to include("No project found matching: nonexistent")
      end
    end

    context "when project management is not configured (no set_default_project)" do
      it "returns the not-configured message" do
        result = call("default MS")
        expect(result).to include("Project management not configured.")
      end
    end
  end

  # -------------------------------------------------------------------------
  # status scoped to default project
  # -------------------------------------------------------------------------

  describe "status with default project" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:project_repo) { WorkCoordinator::Adapters::InMemoryProjectRepository.new }
    let(:uc)           { build_project_use_case(project_repo: project_repo) }
    let(:project)      { build(:project_domain, name: "my-service", alias_attr: "MS") }
    let(:other_proj)   { build(:project_domain, name: "billing") }

    before do
      project_repo.save(project)
      project_repo.save(other_proj)
      project_repo.set_default(project)

      repo.save(build(:work_item_domain, external_reference: "MS-1", title: "MS task",
                                         project_id: project.id))
      repo.save(build(:work_item_domain, external_reference: "BI-1", title: "Billing task",
                                         project_id: other_proj.id))
    end

    it "scopes status to the default project and shows its name" do
      result = uc.call(body: "status")
      expect(result).to include("[MS]")
      expect(result).to include("MS-1")
      expect(result).not_to include("BI-1")
    end
  end

  describe "status with no default project" do
    let(:project_repo) { WorkCoordinator::Adapters::InMemoryProjectRepository.new }
    let(:uc)           { build_project_use_case(project_repo: project_repo) }

    before do
      repo.save(build(:work_item_domain, external_reference: "MS-1", title: "MS task"))
      repo.save(build(:work_item_domain, external_reference: "BI-1", title: "Billing task"))
    end

    it "returns all work items when no default project is set" do
      result = uc.call(body: "status")
      expect(result).to include("MS-1")
      expect(result).to include("BI-1")
    end
  end

  # -------------------------------------------------------------------------
  # status filtered by project alias
  # -------------------------------------------------------------------------

  describe "status <project_alias>" do
    let(:project_repo) { WorkCoordinator::Adapters::InMemoryProjectRepository.new }
    let(:uc)           { build_project_use_case(project_repo: project_repo) }
    let(:project)      { build(:project_domain, name: "my-service", alias_attr: "MS") }

    before do
      project_repo.save(project)
      repo.save(build(:work_item_domain, external_reference: "MS-1", title: "MS task",
                                         project_id: project.id))
      repo.save(build(:work_item_domain, external_reference: "BI-1", title: "Other task",
                                         project_id: nil))
    end

    it "filters work items by project alias" do
      result = uc.call(body: "status MS")
      expect(result).to include("MS-1")
      expect(result).not_to include("BI-1")
    end

    it "still treats state filters as states, not projects" do
      result = uc.call(body: "status active")
      expect(result).not_to include("[MS]")
    end

    context "when the filter fuzzy-matches multiple projects (ambiguous)" do
      # "service-" normalizes to "service_", which is a substring of "my_service_a"
      # and "my_service_b" but NOT of "my_service" (the outer project), so
      # these two are the only candidates and the result is ambiguous.
      before do
        project_repo.save(build(:project_domain, name: "my-service-a", alias_attr: "MSA"))
        project_repo.save(build(:project_domain, name: "my-service-b", alias_attr: "MSB"))
      end

      it "returns an ambiguity message" do
        result = uc.call(body: "status service-")
        expect(result).to include("Ambiguous: matched")
      end
    end

    context "when the filter matches neither a state nor a project" do
      it "returns an unknown-state-or-project message" do
        result = uc.call(body: "status zzzunknown")
        expect(result).to include("Unknown state or project: zzzunknown")
      end
    end
  end
end
