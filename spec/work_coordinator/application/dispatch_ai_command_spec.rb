# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Application::DispatchAiCommand do
  let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }

  def build_use_case(aliases: {}, instruction_context: "", auto_launch_workspace: false,
                     workspace_launch_timeout_seconds: 20, sleep_fn: method(:sleep),
                     clock_fn: -> { Time.now }, **runner_opts)
    runner = WorkCoordinator::Adapters::FakeAiCommandRunner.new(**runner_opts)
    [described_class.new(
      ai_command_runner: runner,
      message_sender: message_sender,
      aliases: aliases,
      instruction_context: instruction_context,
      auto_launch_workspace: auto_launch_workspace,
      workspace_launch_timeout_seconds: workspace_launch_timeout_seconds,
      sleep_fn: sleep_fn,
      clock_fn: clock_fn
    ), runner]
  end

  describe "happy path" do
    let(:use_case_and_runner) do
      build_use_case(
        extract_project_result: "auth",
        list_projects_result: %w[auth-service acme-billing],
        run_project_result: "workspace output here",
        summarize_result: "The auth-service job ran successfully."
      )
    end

    let(:result) { use_case_and_runner.first.call(body: "add error handling to auth service") }
    let(:runner) { use_case_and_runner.last }

    it "returns a dispatched result with the matched project and summary" do
      expect(result.dispatched).to be(true)
      expect(result.project).to eq("auth-service")
      expect(result.summary).to eq("The auth-service job ran successfully.")
      expect(result.failure_reason).to be_nil
    end

    it "calls the runner with the right arguments and sends the summary" do
      result
      expect(runner.extract_project_calls).to eq(["add error handling to auth service"])
      expect(runner.run_project_calls).to eq([
                                               { project: "auth-service",
                                                 instructions: "add error handling to auth service" }
                                             ])
      expect(message_sender.sent_messages.last[:body]).to eq("The auth-service job ran successfully.")
    end
  end

  describe "no workspace match" do
    it "sends a 'No workspace found' notification and returns dispatched: false with failure_reason :no_workspace" do
      use_case, _runner = build_use_case(
        extract_project_result: "unknown-thing",
        list_projects_result: %w[auth-service acme-billing]
      )

      result = use_case.call(body: "do something with unknown-thing")

      expect(result.dispatched).to be(false)
      expect(result.project).to be_nil
      expect(result.summary).to be_nil
      expect(result.failure_reason).to eq(:no_workspace)
      expect(message_sender.sent_messages.last[:body]).to include("No workspace found matching 'unknown-thing'")
    end
  end

  describe "fuzzy match" do
    it "matches keyword 'auth' to project 'auth-service'" do
      use_case, _runner = build_use_case(
        extract_project_result: "auth",
        list_projects_result: %w[auth-service acme-billing],
        run_project_result: "done",
        summarize_result: "Ran auth-service."
      )

      result = use_case.call(body: "fix the auth service")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("auth-service")
    end

    context "with hyphens/underscores" do
      it "matches hyphenated needle to underscored project name" do
        use_case, _runner = build_use_case(
          extract_project_result: "experimentation-service",
          list_projects_result: %w[experimentation_service acme-billing],
          run_project_result: "done",
          summarize_result: "Ran."
        )
        result = use_case.call(body: "fix experimentation-service")
        expect(result.project).to eq("experimentation_service")
      end

      it "matches underscored needle to hyphenated project name" do
        use_case, _runner = build_use_case(
          extract_project_result: "my_project",
          list_projects_result: %w[my-project other-service],
          run_project_result: "done",
          summarize_result: "Ran."
        )
        result = use_case.call(body: "fix my_project")
        expect(result.project).to eq("my-project")
      end
    end
  end

  describe "alias resolution" do
    it "resolves an exact alias match without consulting fuzzy match" do
      use_case, runner = build_use_case(
        aliases: { "MS" => "my-service" },
        extract_project_result: "MS",
        list_projects_result: [],
        run_project_result: "done",
        summarize_result: "Growth engine ran."
      )

      result = use_case.call(body: "run the GE build")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("my-service")
      expect(runner.run_project_calls).to eq([{ project: "my-service", instructions: "run the GE build" }])
    end

    it "matches alias case-insensitively (normalizes keyword to upcase)" do
      use_case, _runner = build_use_case(
        aliases: { "MS" => "my-service" },
        extract_project_result: "ge",
        list_projects_result: [],
        run_project_result: "done",
        summarize_result: "Done."
      )

      result = use_case.call(body: "run ge")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("my-service")
    end

    it "falls back to fuzzy matching when the keyword does not match any alias" do
      use_case, _runner = build_use_case(
        aliases: { "MS" => "my-service" },
        extract_project_result: "auth",
        list_projects_result: %w[auth-service acme-billing],
        run_project_result: "done",
        summarize_result: "Auth ran."
      )

      result = use_case.call(body: "fix auth")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("auth-service")
    end

    it "returns no_workspace when alias resolves but project list is not consulted" do
      use_case, _runner = build_use_case(
        aliases: {},
        extract_project_result: "WC",
        list_projects_result: []
      )

      result = use_case.call(body: "update WC")

      expect(result.dispatched).to be(false)
      expect(result.failure_reason).to eq(:no_workspace)
    end
  end

  describe "instruction_context" do
    it "appends context to the instructions passed to run_project" do
      use_case, runner = build_use_case(
        instruction_context: "How to work:\n\n$rpi",
        extract_project_result: "auth",
        list_projects_result: %w[auth-service],
        run_project_result: "done",
        summarize_result: "Auth ran."
      )

      use_case.call(body: "research foo")

      expect(runner.run_project_calls).to eq([
                                               { project: "auth-service",
                                                 instructions: "research foo\n\nHow to work:\n\n$rpi" }
                                             ])
    end

    it "passes instructions unchanged when instruction_context is empty" do
      use_case, runner = build_use_case(
        instruction_context: "",
        extract_project_result: "auth",
        list_projects_result: %w[auth-service],
        run_project_result: "done",
        summarize_result: "Auth ran."
      )

      use_case.call(body: "research foo")

      expect(runner.run_project_calls).to eq([
                                               { project: "auth-service", instructions: "research foo" }
                                             ])
    end
  end

  describe "no projects available" do
    it "takes the no-workspace path when the project list is empty" do
      use_case, _runner = build_use_case(
        extract_project_result: "auth",
        list_projects_result: []
      )

      result = use_case.call(body: "fix the auth service")

      expect(result.dispatched).to be(false)
      expect(result.failure_reason).to eq(:no_workspace)
    end
  end

  describe "GitHub URL extraction" do
    it "extracts repo name from a GitHub PR URL without calling the AI runner" do
      use_case, runner = build_use_case(
        list_projects_result: %w[my-service acme-billing],
        run_project_result: "done",
        summarize_result: "Growth engine ran."
      )

      result = use_case.call(body: "https://github.com/acme/my-service/pull/830")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("my-service")
      expect(runner.extract_project_calls).to be_empty
    end

    it "fuzzy-matches a GitHub repo name against the project list when a URL is present" do
      use_case, runner = build_use_case(
        list_projects_result: %w[my-service acme-billing],
        run_project_result: "done",
        summarize_result: "Done."
      )

      result = use_case.call(body: "check https://github.com/acme/my-service/pull/830")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("my-service")
      expect(runner.extract_project_calls).to be_empty
    end

    it "falls back to AI extraction when no GitHub URL is present" do
      use_case, runner = build_use_case(
        extract_project_result: "auth",
        list_projects_result: %w[auth-service],
        run_project_result: "done",
        summarize_result: "Auth ran."
      )

      use_case.call(body: "fix the auth service")

      expect(runner.extract_project_calls).to eq(["fix the auth service"])
    end

    it "returns no_workspace when URL repo name has no matching project" do
      use_case, _runner = build_use_case(
        list_projects_result: %w[acme-billing],
        list_all_projects_result: %w[acme-billing]
      )

      result = use_case.call(body: "https://github.com/acme/my-service/pull/830")

      expect(result.dispatched).to be(false)
      expect(result.failure_reason).to eq(:no_workspace)
    end

    describe "URL-based workspace matching" do
      it "matches via git remote URL (ssh format without .git)" do
        use_case, _runner = build_use_case(
          list_all_projects_with_urls_result: [
            { name: "my-service", url: "git@github.com:acme/my-service" }
          ],
          list_projects_result: %w[my-service],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/acme/my-service/pull/830")

        expect(result.dispatched).to be(true)
        expect(result.project).to eq("my-service")
      end

      it "matches via git remote URL (ssh format with .git suffix)" do
        use_case, _runner = build_use_case(
          list_all_projects_with_urls_result: [
            { name: "my-service", url: "git@github.com:acme/my-service.git" }
          ],
          list_projects_result: %w[my-service],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/acme/my-service/pull/830")

        expect(result.dispatched).to be(true)
        expect(result.project).to eq("my-service")
      end

      it "prefers exact name match over worktree name when multiple workspaces share the same remote" do
        use_case, _runner = build_use_case(
          list_all_projects_with_urls_result: [
            { name: "my-service-pr-826", url: "git@github.com:acme/my-service" },
            { name: "my-service", url: "git@github.com:acme/my-service" }
          ],
          list_projects_result: %w[my-service my-service-pr-826],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/acme/my-service/pull/830")

        expect(result.dispatched).to be(true)
        expect(result.project).to eq("my-service")
      end

      it "does NOT match billing-client for a billing URL" do
        use_case, _runner = build_use_case(
          list_all_projects_with_urls_result: [
            { name: "billing", url: "git@github.com:acme/billing.git" },
            { name: "billing-client", url: "git@github.com:acme/billing-client.git" }
          ],
          list_projects_result: %w[billing billing-client],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/acme/billing/pull/1")

        expect(result.dispatched).to be(true)
        expect(result.project).to eq("billing")
      end

      it "falls back to fuzzy name match when workspace url is nil" do
        use_case, _runner = build_use_case(
          list_all_projects_with_urls_result: [
            { name: "my-service", url: nil }
          ],
          list_projects_result: %w[my-service],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/acme/my-service/pull/830")

        expect(result.dispatched).to be(true)
        expect(result.project).to eq("my-service")
      end

      it "matches via git remote URL with trailing slash" do
        use_case, _runner = build_use_case(
          list_all_projects_with_urls_result: [
            { name: "my-service", url: "https://github.com/acme/my-service/" }
          ],
          list_projects_result: %w[my-service],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/acme/my-service/pull/830")

        expect(result.dispatched).to be(true)
        expect(result.project).to eq("my-service")
      end

      it "falls back to fuzzy name match when no workspace URL matches" do
        use_case, _runner = build_use_case(
          list_all_projects_with_urls_result: [
            { name: "my-service", url: "git@github.com:acme/my-service" },
            { name: "billing", url: "git@github.com:acme/billing" }
          ],
          list_projects_result: %w[my-service billing],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/acme/other-repo/pull/5")

        expect(result.dispatched).to be(false)
        expect(result.failure_reason).to eq(:no_workspace)
      end
    end
  end

  describe "auto-launch dormant workspace" do
    let(:no_sleep) { ->(_) {} }

    context "when auto_launch_workspace is false" do
      it "returns dormant_workspace when the project is dormant" do
        use_case, runner = build_use_case(
          auto_launch_workspace: false,
          sleep_fn: no_sleep,
          list_all_projects_result: %w[dormant-project],
          list_projects_result: [],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/org/dormant-project/pull/1")

        expect(result.dispatched).to be(false)
        expect(result.failure_reason).to eq(:dormant_workspace)
        expect(runner.launch_workspace_calls).to be_empty
      end

      it "proceeds normally when project is already active" do
        use_case, runner = build_use_case(
          auto_launch_workspace: false,
          sleep_fn: no_sleep,
          list_all_projects_result: %w[active-project],
          list_projects_result: %w[active-project],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/org/active-project/pull/1")

        expect(result.dispatched).to be(true)
        expect(runner.launch_workspace_calls).to be_empty
      end
    end

    context "when auto_launch_workspace is true" do
      it "launches and delivers when project appears within timeout" do
        use_case, runner = build_use_case(
          auto_launch_workspace: true,
          workspace_launch_timeout_seconds: 10,
          sleep_fn: no_sleep,
          list_all_projects_result: %w[slow-project],
          list_projects_results: [[], %w[slow-project]],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/org/slow-project/pull/1")

        expect(result.dispatched).to be(true)
        expect(runner.launch_workspace_calls).to eq(["slow-project"])
      end

      it "skips launch when project is already active" do
        use_case, runner = build_use_case(
          auto_launch_workspace: true,
          sleep_fn: no_sleep,
          list_all_projects_result: %w[active-project],
          list_projects_result: %w[active-project],
          run_project_result: "done",
          summarize_result: "Done."
        )

        result = use_case.call(body: "https://github.com/org/active-project/pull/1")

        expect(result.dispatched).to be(true)
        expect(runner.launch_workspace_calls).to be_empty
      end

      it "returns launch_timeout when project never appears" do
        use_case, _runner = build_use_case(
          auto_launch_workspace: true,
          workspace_launch_timeout_seconds: 0,
          sleep_fn: no_sleep,
          list_all_projects_result: %w[stuck-project],
          list_projects_result: []
        )

        result = use_case.call(body: "https://github.com/org/stuck-project/pull/1")

        expect(result.dispatched).to be(false)
        expect(result.failure_reason).to eq(:launch_timeout)
        expect(message_sender.sent_messages.last[:body]).to include("Workspace stuck-project did not start within 0s")
      end

      it "does not auto-launch for AI-extracted (non-URL) dispatch" do
        use_case, runner = build_use_case(
          auto_launch_workspace: true,
          sleep_fn: no_sleep,
          extract_project_result: "some-project",
          list_projects_result: %w[some-project],
          run_project_result: "done",
          summarize_result: "Done."
        )

        use_case.call(body: "fix the some-project service")

        expect(runner.launch_workspace_calls).to be_empty
      end
    end
  end
end
