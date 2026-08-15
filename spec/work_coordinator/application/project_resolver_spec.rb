# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Application::ProjectResolver do
  let(:repo)     { WorkCoordinator::Adapters::InMemoryProjectRepository.new }
  let(:resolver) { described_class.new(project_repo: repo) }

  def save_project(name:, alias_attr: nil)
    project = build(:project_domain, name: name, alias_attr: alias_attr)
    repo.save(project)
    project
  end

  describe "#resolve" do
    context "with nil or empty query" do
      it "returns :not_found for nil" do
        expect(resolver.resolve(nil).status).to eq(:not_found)
      end

      it "returns :not_found for an empty string" do
        expect(resolver.resolve("").status).to eq(:not_found)
      end

      it "returns :not_found for a blank string" do
        expect(resolver.resolve("   ").status).to eq(:not_found)
      end
    end

    context "with an exact name match" do
      let!(:project) { save_project(name: "my-service") }

      it "returns :found" do
        result = resolver.resolve("my-service")
        expect(result).to be_found
        expect(result.project.id).to eq(project.id)
      end

      it "is case-insensitive" do
        expect(resolver.resolve("MY-SERVICE")).to be_found
      end
    end

    context "with an exact alias match" do
      let!(:project) { save_project(name: "my-service", alias_attr: "MS") }

      it "returns :found via the alias" do
        result = resolver.resolve("MS")
        expect(result).to be_found
        expect(result.project.id).to eq(project.id)
      end

      it "is case-insensitive for the alias" do
        expect(resolver.resolve("ms")).to be_found
      end
    end

    context "with a single fuzzy substring match" do
      let!(:project) { save_project(name: "my-service") }

      it "returns :found when the needle is a substring of the name" do
        result = resolver.resolve("my")
        expect(result).to be_found
        expect(result.project.id).to eq(project.id)
      end
    end

    context "with multiple fuzzy matches" do
      let!(:proj_a) { save_project(name: "my-service-a") }
      let!(:proj_b) { save_project(name: "my-service-b") }

      it "returns :ambiguous and lists candidates" do
        result = resolver.resolve("my-service")
        expect(result).to be_ambiguous
        expect(result.candidates.map(&:id)).to contain_exactly(proj_a.id, proj_b.id)
      end
    end

    context "when nothing matches" do
      before { save_project(name: "billing") }

      it "returns :not_found" do
        expect(resolver.resolve("unknown-project")).to be_not_found
      end
    end

    context "when a project has no alias" do
      before { save_project(name: "no-alias-project", alias_attr: nil) }

      it "does not crash during fuzzy matching" do
        expect { resolver.resolve("no-alias") }.not_to raise_error
      end
    end
  end
end
