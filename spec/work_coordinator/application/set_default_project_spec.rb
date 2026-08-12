# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Application::SetDefaultProject do
  let(:repo)     { WorkCoordinator::Adapters::InMemoryProjectRepository.new }
  let(:resolver) { WorkCoordinator::Application::ProjectResolver.new(project_repo: repo) }
  let(:use_case) { described_class.new(project_repo: repo, project_resolver: resolver) }

  def save_project(name:, alias_attr: nil)
    project = build(:project_domain, name: name, alias_attr: alias_attr)
    repo.save(project)
    project
  end

  describe "#call" do
    context "when the query matches exactly" do
      let!(:project) { save_project(name: "my-service", alias_attr: "MS") }

      it "returns success with a message mentioning alias and name" do
        result = use_case.call(query: "my-service")
        expect(result.success).to be(true)
        expect(result.message).to include("MS")
        expect(result.message).to include("my-service")
      end

      it "marks the project as the default" do
        use_case.call(query: "MS")
        expect(repo.default_project.id).to eq(project.id)
      end
    end

    context "when the query is a single fuzzy match" do
      let!(:project) { save_project(name: "acme-billing") }

      it "treats the fuzzy match as found and sets it as default" do
        result = use_case.call(query: "billing")
        expect(result.success).to be(true)
        expect(repo.default_project.id).to eq(project.id)
      end
    end

    context "when the query is ambiguous" do
      before do
        save_project(name: "my-service-a", alias_attr: "GEA")
        save_project(name: "my-service-b", alias_attr: "GEB")
      end

      it "returns failure with an ambiguity message" do
        result = use_case.call(query: "my-service")
        expect(result.success).to be(false)
        expect(result.failure_reason).to eq(:ambiguous)
        expect(result.message).to include("GEA").or include("GEB")
      end
    end

    context "when nothing matches" do
      it "returns failure mentioning the query" do
        result = use_case.call(query: "nonexistent")
        expect(result.success).to be(false)
        expect(result.failure_reason).to eq(:not_found)
        expect(result.message).to include("nonexistent")
      end
    end
  end
end
