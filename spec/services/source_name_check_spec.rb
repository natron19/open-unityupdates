require "rails_helper"

RSpec.describe SourceNameCheck do
  let(:sources) { "Board minutes, March 12 meeting (document)\nInes Calloway, treasurer (interview)" }

  def claim(state, source_name)
    { "state" => state, "source_name" => source_name }
  end

  describe ".unlisted" do
    it "passes names that appear in the sources list, ignoring case and spacing" do
      claims = [ claim("sourced", "Board minutes, March 12 meeting"), claim("single_source", "ines  CALLOWAY") ]
      expect(described_class.unlisted(claims, sources)).to be_empty
    end

    it "checks each name of a claim backed by two sources" do
      expect(described_class.unlisted([ claim("sourced", "Board minutes; Ines Calloway") ], sources)).to be_empty
      expect(described_class.unlisted([ claim("sourced", "Board minutes; County records") ], sources)).to eq([ "County records" ])
    end

    it "passes a listed name with a parenthetical or a description after a comma" do
      claims = [ claim("sourced", "Board minutes (March 12)"), claim("single_source", "Ines Calloway, the treasurer") ]
      expect(described_class.unlisted(claims, sources)).to be_empty
    end

    it "flags an invented source" do
      expect(described_class.unlisted([ claim("single_source", "A source at town hall") ], sources)).to eq([ "A source at town hall" ])
      expect(described_class.unlisted([ claim("single_source", "County records (2024)") ], sources)).to eq([ "County records (2024)" ])
    end

    it "flags any named source when the reporter listed none" do
      expect(described_class.unlisted([ claim("single_source", "Ines Calloway") ], "")).to eq([ "Ines Calloway" ])
      expect(described_class.unlisted([ claim("sourced", "Ines Calloway") ], nil)).to eq([ "Ines Calloway" ])
    end

    it "matches on word boundaries and ignores names under three characters" do
      expect(described_class.unlisted([ claim("single_source", "Callow") ], sources)).to eq([ "Callow" ])
      expect(described_class.unlisted([ claim("single_source", "In") ], sources)).to eq([ "In" ])
    end

    it "ignores unsourced claims" do
      expect(described_class.unlisted([ claim("unsourced", "none") ], sources)).to be_empty
    end
  end

  describe ".none?" do
    it "treats blank, none, n/a and no source as no source" do
      [ "", "none", "None", " NONE ", "n/a", "No source" ].each { |v| expect(described_class.none?(v)).to be(true) }
      expect(described_class.none?("Ines Calloway")).to be(false)
    end
  end
end
