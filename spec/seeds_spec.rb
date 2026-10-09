require "rails_helper"

RSpec.describe "db/seeds.rb" do
  def load_seeds
    expect { Rails.application.load_seed }.to output.to_stdout
  end

  before { load_seeds }

  let(:template) { AiTemplate.find_by!(name: "unityupdates_source_check_v1") }
  let(:example)  { StoryDraft.find_by!(headline: "Board moves to sell the Fenwick Street garden lot") }

  it "seeds the source check template with JSON-safe settings and no placeholder" do
    expect(template.model).to eq("gemini-2.5-flash")
    expect(template.max_output_tokens).to eq(8192)
    expect(template.variable_names).to contain_exactly("headline", "label", "beat", "sources_text", "notes")
    expect(AiTemplate.where(name: "demo_placeholder_v1")).to be_empty
  end

  it "carries production's hard rules in the system prompt" do
    expect(template.system_prompt).to include(
      "You never write story prose", "A Reporter writes every word", "Never invent a source",
      "Never invent a person's name", "You flag; you never rule"
    )
  end

  it "seeds one fictional example draft for the demo user with a completed check that passes the parser" do
    check = example.source_checks.sole
    expect(example.user.email).to eq("demo@example.com")
    expect(check.status).to eq("completed")

    controller = SourceChecksController.new
    controller.instance_variable_set(:@story_draft, example)
    parsed = controller.send(:parse_source_check!, check.gemini_raw)
    expect(parsed[:claims]).to eq(check.claims)
    expect(parsed[:questions_to_ask]).to eq(check.questions_to_ask)
  end

  it "is idempotent" do
    expect { load_seeds }.not_to change { [ AiTemplate.count, StoryDraft.count, SourceCheck.count ] }
  end

  it "keeps the rendered prompt under the gatekeeper's length cap with every field at its maximum" do
    draft = build(:story_draft, headline: "h" * StoryDraft::HEADLINE_MAX, beat: "b" * StoryDraft::BEAT_MAX,
                                notes: "n" * StoryDraft::NOTES_RANGE.max, sources_text: "s" * StoryDraft::SOURCES_MAX,
                                label: StoryDraft::LABEL_PROMPTS.max_by { |_, v| v.length }.first)
    expect(template.interpolate(draft.ai_variables).length).to be < AiGatekeeper::MAX_INPUT_LENGTH
  end
end
