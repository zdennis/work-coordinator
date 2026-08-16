# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Domain::RoleToken do
  describe ".split" do
    # The protocol grammar's worked examples, with the ai: prefix already stripped.
    {
      "MS - add validation" => [nil, "MS - add validation"],
      "claude MS - add validation" => [nil, "claude MS - add validation"],
      "home: claude MS - add validation" => ["home", "claude MS - add validation"],
      "h: MS - add validation" => ["h", "MS - add validation"],
      "work: new MS - add validation" => ["work", "new MS - add validation"]
    }.each do |body, expected|
      it "splits #{body.inspect} into #{expected.inspect}" do
        expect(described_class.split(body)).to eq(expected)
      end
    end

    it "downcases the role" do
      expect(described_class.split("HOME: MS - go")).to eq(["home", "MS - go"])
    end

    it "accepts a role with no body after it" do
      expect(described_class.split("home:")).to eq(["home", ""])
    end

    it "does not treat a word separated from its colon as a role" do
      expect(described_class.split("home - fix it")).to eq([nil, "home - fix it"])
    end

    it "does not treat a colon with no whitespace after it as a role" do
      expect(described_class.split("see https://example.com")).to eq([nil, "see https://example.com"])
    end

    it "does not treat a slash command as a role" do
      expect(described_class.split("/build MS add OAuth")).to eq([nil, "/build MS add OAuth"])
    end

    it "leaves a colon later in the body alone" do
      expect(described_class.split("MS - note: be careful")).to eq([nil, "MS - note: be careful"])
    end

    it "handles nil" do
      expect(described_class.split(nil)).to eq([nil, ""])
    end
  end
end
