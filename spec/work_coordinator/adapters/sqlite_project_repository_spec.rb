# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Adapters::SqliteProjectRepository do
  subject(:repo) { described_class.new }

  def build_project(overrides = {})
    build(:project_domain, **overrides)
  end

  # -----------------------------------------------------------------------
  # save + find round-trip
  # -----------------------------------------------------------------------

  describe "#save and #find" do
    it "persists and retrieves a project by id" do
      project = build_project(name: "my-service", alias_attr: "MS")
      repo.save(project)

      found = repo.find(project.id)
      expect(found).to have_attributes(id: project.id, name: "my-service", alias: "MS")
    end

    it "returns nil when the id is unknown" do
      expect(repo.find("nonexistent")).to be_nil
    end

    it "updates the record on a second save with the same id" do
      project = build_project(name: "old-name")
      repo.save(project)
      repo.save(project.with(name: "new-name"))

      expect(repo.find(project.id).name).to eq("new-name")
    end
  end

  # -----------------------------------------------------------------------
  # find_by_name_or_alias
  # -----------------------------------------------------------------------

  describe "#find_by_name_or_alias" do
    before { repo.save(build_project(name: "my-service", alias_attr: "MS")) }

    it "matches by exact name" do
      result = repo.find_by_name_or_alias("my-service")
      expect(result.name).to eq("my-service")
    end

    it "matches by exact alias" do
      result = repo.find_by_name_or_alias("MS")
      expect(result.alias).to eq("MS")
    end

    it "is case-insensitive for name" do
      expect(repo.find_by_name_or_alias("GROWTH-ENGINE")).not_to be_nil
    end

    it "is case-insensitive for alias" do
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
    it "returns an empty array when no projects exist" do
      expect(repo.find_all).to eq([])
    end

    it "returns all saved projects" do
      repo.save(build_project(name: "project-a"))
      repo.save(build_project(name: "project-b"))

      names = repo.find_all.map(&:name)
      expect(names).to contain_exactly("project-a", "project-b")
    end
  end

  # -----------------------------------------------------------------------
  # default_project
  # -----------------------------------------------------------------------

  describe "#default_project" do
    it "returns nil when no project has is_default set" do
      repo.save(build_project)
      expect(repo.default_project).to be_nil
    end

    it "returns the project flagged as default" do
      repo.save(build_project(name: "other"))
      default_project = build_project(name: "the-default", is_default: true)
      repo.save(default_project)

      expect(repo.default_project.name).to eq("the-default")
    end
  end

  # -----------------------------------------------------------------------
  # set_default
  # -----------------------------------------------------------------------

  describe "#set_default" do
    it "sets the given project as default and clears the previous one" do
      first  = repo.save(build_project(name: "first",  is_default: true))
      second = repo.save(build_project(name: "second", is_default: false))

      repo.set_default(second)

      expect(repo.find(first.id).is_default).to be(false)
      expect(repo.find(second.id).is_default).to be(true)
    end

    it "returns the saved default project" do
      project = repo.save(build_project(name: "new-default"))
      result  = repo.set_default(project)

      expect(result.is_default).to be(true)
      expect(result.name).to eq("new-default")
    end
  end

  # -----------------------------------------------------------------------
  # delete
  # -----------------------------------------------------------------------

  describe "#delete" do
    it "removes the project from the store" do
      project = repo.save(build_project)
      repo.delete(project.id)

      expect(repo.find(project.id)).to be_nil
    end

    it "is a no-op for an unknown id" do
      expect { repo.delete("nonexistent") }.not_to raise_error
    end
  end
end
