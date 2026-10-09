require "rails_helper"

RSpec.describe StoryDraft, type: :model do
  describe "validations" do
    it "is valid with the factory attributes" do
      expect(build(:story_draft)).to be_valid
    end

    it "requires a user" do
      expect(build(:story_draft, user: nil)).not_to be_valid
    end

    it "requires a headline of at most 120 characters" do
      expect(build(:story_draft, headline: "")).not_to be_valid
      expect(build(:story_draft, headline: "x" * 121)).not_to be_valid
    end

    it "requires notes of 30 to 3000 characters" do
      expect(build(:story_draft, notes: "")).not_to be_valid
      expect(build(:story_draft, notes: "Too short to check.")).not_to be_valid
      expect(build(:story_draft, notes: "x" * 3001)).not_to be_valid
      expect(build(:story_draft, notes: "x" * 3000)).to be_valid
    end

    it "accepts every known label and rejects others" do
      StoryDraft::LABELS.each { |l| expect(build(:story_draft, label: l)).to be_valid }
      expect(build(:story_draft, label: "rumour")).not_to be_valid
      expect(build(:story_draft, label: nil)).not_to be_valid
    end

    it "allows a blank beat and blank sources but caps them" do
      expect(build(:story_draft, beat: nil, sources_text: nil)).to be_valid
      expect(build(:story_draft, beat: "x" * 81)).not_to be_valid
      expect(build(:story_draft, sources_text: "x" * 1201)).not_to be_valid
    end
  end

  describe "constants" do
    it "lists the four production labels, each with a name, a form option and a prompt phrase" do
      expect(StoryDraft::LABELS).to eq(%w[reported announcement opinion explainer])
      expect(StoryDraft::LABEL_NAMES.keys).to eq(StoryDraft::LABELS)
      expect(StoryDraft::LABEL_OPTIONS.keys).to eq(StoryDraft::LABELS)
      expect(StoryDraft::LABEL_PROMPTS.keys).to eq(StoryDraft::LABELS)
    end
  end

  describe "associations" do
    it "destroys its source checks" do
      draft = create(:story_draft)
      create(:source_check, :completed, story_draft: draft)
      expect { draft.destroy }.to change(SourceCheck, :count).by(-1)
    end

    it "returns the newest check as latest_source_check" do
      draft = create(:story_draft)
      create(:source_check, :completed, story_draft: draft, generated_at: 2.days.ago)
      newest = create(:source_check, :completed, story_draft: draft, generated_at: 1.hour.ago)
      expect(draft.reload.latest_source_check).to eq(newest)
    end

    it "is destroyed with its user" do
      draft = create(:story_draft)
      expect { draft.user.destroy }.to change(StoryDraft, :count).by(-1)
    end
  end

  describe "#ai_variables" do
    it "sends the draft fields and the label phrase, and nothing about the author" do
      draft = build(:story_draft, label: "explainer")
      vars = draft.ai_variables
      expect(vars.keys).to eq(%i[headline label beat sources_text notes])
      expect(vars[:label]).to eq(StoryDraft::LABEL_PROMPTS["explainer"])
      expect(vars.values.join).not_to include(draft.user.name, draft.user.email)
    end

    it "says plainly when there is no beat and no sources" do
      vars = build(:story_draft, beat: "", sources_text: "  ").ai_variables
      expect(vars[:beat]).to eq("Not stated")
      expect(vars[:sources_text]).to eq("No sources listed yet.")
    end
  end

  describe "#input_text" do
    it "joins everything the reporter typed" do
      draft = build(:story_draft)
      expect(draft.input_text).to include(draft.headline, draft.beat, draft.notes, draft.sources_text)
    end
  end
end
