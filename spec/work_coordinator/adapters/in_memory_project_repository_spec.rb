# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Adapters::InMemoryProjectRepository do
  subject(:repo) { described_class.new }

  def build_project(overrides = {})
    build(:project_domain, **overrides)
  end

  # -----------------------------------------------------------------------
  # save + find round-trip
  # -----------------------------------------------------------------------

  describe "#save and #find" do
    it "stores and retrieves a project by id" do
      project = build_project(name: "my-service", alias_attr: "MS")
      repo.save(project)

      found = repo.find(project.id)
      expect(found).to have_attributes(name: "my-service", alias: "MS")
    end

    it "returns nil for an unknown id" do
      expect(repo.find("unknown")).to be_nil
    end

    it "replaces the stored record on a second save with the same id" do
      project = build_project(name: "old")
      repo.save(project)
      repo.save(project.with(name: "new"))

      expect(repo.find(project.id).name).to eq("new")
    end
  end

  # -----------------------------------------------------------------------
  # find_by_name_or_alias
  # -----------------------------------------------------------------------

  describe "#find_by_name_or_alias" do
    before { repo.save(build_project(name: "my-service", alias_attr: "MS")) }

    it "matches by exact name" do
      expect(repo.find_by_name_or_alias("my-service")).not_to be_nil
    end

    it "matches by exact alias" do
      expect(repo.find_by_name_or_alias("MS")).not_to be_nil
    end

    it "is case-insensitive" do
      expect(repo.find_by_name_or_alias("GROWTH-ENGINE")).not_to be_nil
      expect(repo.find_by_name_or_alias("ge")).not_to be_nil
    end

    it "returns nil when nothing matches" do
      expect(repo.find_by_name_or_alias("unknown")).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # find_all
  # -----------------------------------------------------------------------

  describe "#find_all" do
    it "returns an empty array initially" do
      expect(repo.find_all).to eq([])
    end

    it "returns all saved projects" do
      repo.save(build_project(name: "a"))
      repo.save(build_project(name: "b"))

      expect(repo.find_all.map(&:name)).to contain_exactly("a", "b")
    end
  end

  # -----------------------------------------------------------------------
  # default_project
  # -----------------------------------------------------------------------

  describe "#default_project" do
    it "returns nil when no project is default" do
      repo.save(build_project(is_default: false))
      expect(repo.default_project).to be_nil
    end

    it "returns the default project" do
      repo.save(build_project(name: "other", is_default: false))
      default_p = build_project(name: "mine", is_default: true)
      repo.save(default_p)

      expect(repo.default_project.name).to eq("mine")
    end
  end

  # -----------------------------------------------------------------------
  # set_default
  # -----------------------------------------------------------------------

  describe "#set_default" do
    it "clears is_default on all others and marks only the target as default" do
      first  = repo.save(build_project(name: "first",  is_default: true))
      second = repo.save(build_project(name: "second", is_default: false))

      repo.set_default(second)

      expect(repo.find(first.id).is_default).to be(false)
      expect(repo.find(second.id).is_default).to be(true)
    end

    it "returns the saved default" do
      project = repo.save(build_project(name: "p"))
      result  = repo.set_default(project)

      expect(result.is_default).to be(true)
    end
  end

  # -----------------------------------------------------------------------
  # delete
  # -----------------------------------------------------------------------

  describe "#delete" do
    it "removes the project" do
      project = repo.save(build_project)
      repo.delete(project.id)

      expect(repo.find(project.id)).to be_nil
    end

    it "is silent for unknown ids" do
      expect { repo.delete("missing") }.not_to raise_error
    end
  end
end
