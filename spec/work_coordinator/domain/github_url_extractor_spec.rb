# frozen_string_literal: true

require "work_coordinator/domain/github_url_extractor"

RSpec.describe WorkCoordinator::Domain::GithubUrlExtractor do
  subject(:extractor) { described_class.new(text) }

  describe "#repo_name" do
    context "with a pull request URL" do
      let(:text) { "https://github.com/acme/my-service/pull/830" }

      it { expect(extractor.repo_name).to eq("my-service") }
    end

    context "with an issue URL" do
      let(:text) { "https://github.com/acme/billing/issues/42" }

      it { expect(extractor.repo_name).to eq("billing") }
    end

    context "with a bare repo URL" do
      let(:text) { "https://github.com/acme/work-coordinator" }

      it { expect(extractor.repo_name).to eq("work-coordinator") }
    end

    context "with a URL embedded in surrounding text" do
      let(:text) { "see PR https://github.com/acme/my-service/pull/830 for context" }

      it { expect(extractor.repo_name).to eq("my-service") }
    end

    context "with an http (non-https) URL" do
      let(:text) { "http://github.com/acme/billing/pull/1" }

      it { expect(extractor.repo_name).to eq("billing") }
    end

    context "with no URL" do
      let(:text) { "plain text no url" }

      it { expect(extractor.repo_name).to be_nil }
    end

    context "with a non-GitHub URL" do
      let(:text) { "https://gitlab.com/acme/my-service/pull/1" }

      it { expect(extractor.repo_name).to be_nil }
    end

    context "with an empty string" do
      let(:text) { "" }

      it { expect(extractor.repo_name).to be_nil }
    end

    context "with nil" do
      let(:text) { nil }

      it { expect(extractor.repo_name).to be_nil }
    end

    context "when multiple GitHub URLs are present" do
      let(:text) { "from https://github.com/acme/billing/pull/5 to https://github.com/acme/auth/pull/9" }

      it "returns the first repo name found" do
        expect(extractor.repo_name).to eq("billing")
      end
    end
  end

  describe "#owner_repo" do
    context "with a pull request URL" do
      let(:text) { "https://github.com/acme/my-service/pull/830" }

      it { expect(extractor.owner_repo).to eq("acme/my-service") }
    end

    context "with an issue URL" do
      let(:text) { "https://github.com/acme/billing/issues/42" }

      it { expect(extractor.owner_repo).to eq("acme/billing") }
    end

    context "with a bare repo URL" do
      let(:text) { "https://github.com/acme/work-coordinator" }

      it { expect(extractor.owner_repo).to eq("acme/work-coordinator") }
    end

    context "with a URL embedded in surrounding text" do
      let(:text) { "see PR https://github.com/acme/billing-client/pull/5 for context" }

      it { expect(extractor.owner_repo).to eq("acme/billing-client") }
    end

    context "with an http (non-https) URL" do
      let(:text) { "http://github.com/acme/billing/pull/1" }

      it { expect(extractor.owner_repo).to eq("acme/billing") }
    end

    context "with no URL" do
      let(:text) { "plain text no url" }

      it { expect(extractor.owner_repo).to be_nil }
    end

    context "with a non-GitHub URL" do
      let(:text) { "https://gitlab.com/acme/my-service/pull/1" }

      it { expect(extractor.owner_repo).to be_nil }
    end

    context "with nil" do
      let(:text) { nil }

      it { expect(extractor.owner_repo).to be_nil }
    end

    context "when multiple GitHub URLs are present" do
      let(:text) { "from https://github.com/acme/billing/pull/5 to https://github.com/acme/auth/pull/9" }

      it "returns the owner/repo of the first GitHub URL found" do
        expect(extractor.owner_repo).to eq("acme/billing")
      end
    end
  end
end
