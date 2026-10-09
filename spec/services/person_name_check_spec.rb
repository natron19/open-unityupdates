require "rails_helper"

RSpec.describe PersonNameCheck do
  let(:input) do
    "Board moves to sell the Fenwick Street garden lot\n" \
      "The board voted 5-2. Treasurer Ines Calloway said the sale would pay for the roof.\n" \
      "Ines Calloway, treasurer (interview)"
  end

  describe ".names_in" do
    def fulls(text)    = described_class.names_in(text).map(&:full).compact
    def surnames(text) = described_class.names_in(text).map(&:surname)

    it "finds a first and last name" do
      expect(fulls("Ask Dana Whitlock when she heard.")).to eq([ "Dana Whitlock" ])
    end

    it "finds a surname after a title, with or without a period" do
      expect(surnames("Councillor Brannigan agrees, and so does Ms. Okafor.")).to contain_exactly("Brannigan", "Okafor")
    end

    it "ignores places, organizations, days, months, and records" do
      text = "Request the Westbrook Water District minutes. Did Harbor Lane Tenants Association hear in March? Read the Alder Park Neighbors Bulletin."
      expect(described_class.names_in(text)).to be_empty
    end

    it "ignores question words and imperative verbs at the start of a line" do
      expect(described_class.names_in("Did Gardeners hear first?\nConfirm Saturday hours.")).to be_empty
    end

    it "ignores a title-cased headline" do
      expect(described_class.names_in("Board Moves To Sell The Garden Lot")).to be_empty
    end
  end

  describe ".invented_in" do
    it "passes names that are in the input, in any case, and surnames alone" do
      output = "Ask Ines Calloway for the quote.\nWas calloway at the meeting?\nCalloway said so."
      expect(described_class.invented_in(output, input)).to be_empty
    end

    it "flags a full name that is not in the input" do
      expect(described_class.invented_in("Ask Dana Whitlock, a gardener, when she heard.", input)).to eq([ "Dana Whitlock" ])
    end

    it "flags a titled name that is not in the input" do
      expect(described_class.invented_in("Call Councillor Brannigan about the vote.", input)).to eq([ "Brannigan" ])
    end

    it "passes roles, places, and organizations" do
      output = "Ask the treasurer for the appraisal.\nRequest the Fenwick Street plot list from the garden coordinator.\nDid the City Council see it?"
      expect(described_class.clean?(output, input)).to be(true)
    end

    it "does not flag a capitalized phrase whose last word the text also uses in lowercase" do
      expect(described_class.invented_in("Ask the coordinator about Harvest Swaps. Gardeners run the swaps.", input)).to be_empty
      expect(described_class.invented_in("Ask the coordinator about Harvest Swaps.", input)).to eq([ "Harvest Swaps" ])
    end

    it "flags every invented name once" do
      output = "Ask Dana Whitlock.\nAsk Dana Whitlock again.\nCall Mayor Ortiz."
      expect(described_class.invented_in(output, input)).to eq([ "Dana Whitlock", "Ortiz" ])
    end
  end
end
