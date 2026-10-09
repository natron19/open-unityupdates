require "rails_helper"

RSpec.describe SourceCheck, type: :model do
  describe "validations" do
    it "is valid with the factory attributes" do
      expect(build(:source_check)).to be_valid
    end

    it "requires a story draft" do
      expect(build(:source_check, story_draft: nil)).not_to be_valid
    end

    it "accepts every known status and rejects others" do
      SourceCheck::STATUSES.each { |s| expect(build(:source_check, status: s)).to be_valid }
      expect(build(:source_check, status: "unknown")).not_to be_valid
    end
  end

  describe "constants" do
    it "lists the statuses and the three production claim states" do
      expect(SourceCheck::STATUSES).to eq(%w[pending completed failed])
      expect(SourceCheck::CLAIM_STATES).to eq(%w[sourced single_source unsourced])
      expect(SourceCheck::CLAIM_STATE_NAMES.keys).to eq(SourceCheck::CLAIM_STATES)
    end
  end

  describe "associations" do
    it "has a user through its story draft" do
      check = create(:source_check)
      expect(check.user).to eq(check.story_draft.user)
    end
  end

  describe "defaults" do
    it "starts pending with empty lists" do
      check = SourceCheck.create!(story_draft: create(:story_draft))
      expect(check.status).to eq("pending")
      expect([ check.claims, check.affected_not_heard, check.loaded_words, check.questions_to_ask ]).to all(eq([]))
    end
  end

  describe "#state_counts and #summary_line" do
    it "counts claims per state" do
      check = build(:source_check, :completed)
      expect(check.state_counts).to eq("sourced" => 1, "single_source" => 1, "unsourced" => 1)
      expect(check.summary_line).to eq("1 sourced · 1 single source · 1 unsourced")
    end

    it "says so when there are no claims" do
      expect(build(:source_check, :completed, claims: []).summary_line).to eq("No factual claims found")
    end
  end

  describe "#stale?" do
    it "is true when the draft changed after the check" do
      check = create(:source_check, :completed, generated_at: 1.hour.ago)
      check.story_draft.update!(headline: "A newer headline")
      expect(check.stale?).to be(true)
    end

    it "is false when the check is newer than the draft" do
      check = create(:source_check, :completed, generated_at: 1.minute.from_now)
      expect(check.stale?).to be(false)
    end
  end

  describe "#to_markdown" do
    it "includes every section and the sources list" do
      check = create(:source_check, :completed)
      md = check.to_markdown
      expect(md).to include("# Source check: #{check.story_draft.headline}")
      expect(md).to include("AI-generated: a checklist, not a ruling")
      expect(md).to include("1. **Sourced**: The pantry will close on Saturdays from October 4.")
      expect(md).to include("   - Source: Tomas Reyes", "**Unsourced**")
      expect(md).to include("## Affected but not heard", "Families who can only come on Saturdays")
      expect(md).to include("**abandoned**: a judgement, not a fact")
      expect(md).to include(*check.questions_to_ask, check.label_fit)
      expect(md).to include("## Sources listed", "Tomas Reyes, pantry coordinator (interview)")
    end

    it "handles empty lists and no sources" do
      draft = create(:story_draft, sources_text: "")
      md = create(:source_check, :completed, story_draft: draft, claims: [], affected_not_heard: [], loaded_words: []).to_markdown
      expect(md).to include("No factual claims found in the notes.", "Nobody obvious.", "None flagged.", "None yet.")
    end

    it "names the file after the headline" do
      check = create(:source_check, :completed)
      expect(check.markdown_filename).to eq("northgate-food-pantry-cuts-saturday-hours-source-check.md")
    end
  end
end
