# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Application::DispatchAiCommand do
  let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }

  def build_use_case(aliases: {}, **runner_opts)
    runner = WorkCoordinator::Adapters::FakeAiCommandRunner.new(**runner_opts)
    [described_class.new(ai_command_runner: runner, message_sender: message_sender, aliases: aliases), runner]
  end

  describe "happy path" do
    let(:use_case_and_runner) do
      build_use_case(
        extract_project_result: "auth",
        list_projects_result: %w[auth-service billing-service],
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
        list_projects_result: %w[auth-service billing-service]
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
        list_projects_result: %w[auth-service billing-service],
        run_project_result: "done",
        summarize_result: "Ran auth-service."
      )

      result = use_case.call(body: "fix the auth service")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("auth-service")
    end
  end

  describe "alias resolution" do
    it "resolves an exact alias match without consulting fuzzy match" do
      use_case, runner = build_use_case(
        aliases: { "GE" => "growth-engine" },
        extract_project_result: "GE",
        list_projects_result: [],
        run_project_result: "done",
        summarize_result: "Growth engine ran."
      )

      result = use_case.call(body: "run the GE build")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("growth-engine")
      expect(runner.run_project_calls).to eq([{ project: "growth-engine", instructions: "run the GE build" }])
    end

    it "matches alias case-insensitively (normalizes keyword to upcase)" do
      use_case, _runner = build_use_case(
        aliases: { "GE" => "growth-engine" },
        extract_project_result: "ge",
        list_projects_result: [],
        run_project_result: "done",
        summarize_result: "Done."
      )

      result = use_case.call(body: "run ge")

      expect(result.dispatched).to be(true)
      expect(result.project).to eq("growth-engine")
    end

    it "falls back to fuzzy matching when the keyword does not match any alias" do
      use_case, _runner = build_use_case(
        aliases: { "GE" => "growth-engine" },
        extract_project_result: "auth",
        list_projects_result: %w[auth-service billing-service],
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
end
