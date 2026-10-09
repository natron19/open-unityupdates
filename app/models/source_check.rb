class SourceCheck < ApplicationRecord
  belongs_to :story_draft
  has_one :user, through: :story_draft

  STATUSES     = %w[pending completed failed].freeze
  CLAIM_STATES = %w[sourced single_source unsourced].freeze

  CLAIM_STATE_NAMES = {
    "sourced"       => "Sourced",
    "single_source" => "Single source",
    "unsourced"     => "Unsourced"
  }.freeze

  validates :status, inclusion: { in: STATUSES }

  def completed? = status == "completed"
  def failed?    = status == "failed"

  # The draft was edited after this check ran.
  def stale?
    generated_at.present? && story_draft.updated_at > generated_at
  end

  # { "sourced" => 2, "single_source" => 1, "unsourced" => 3 }, every state present.
  def state_counts
    CLAIM_STATES.index_with { |state| claims.count { |c| c["state"] == state } }
  end

  # "2 sourced · 1 single source · 3 unsourced"
  def summary_line
    return "No factual claims found" if claims.empty?
    state_counts.map { |state, n| "#{n} #{CLAIM_STATE_NAMES[state].downcase}" }.join(" · ")
  end

  def self.state_name(state)
    CLAIM_STATE_NAMES.fetch(state, state.to_s.humanize)
  end

  def to_markdown
    draft = story_draft
    lines = []
    lines << "# Source check: #{draft.headline}"
    lines << ""
    lines << "_Generated #{generated_at&.strftime('%Y-%m-%d') || 'unknown'} by #{ENV.fetch('APP_NAME', 'UnityUpdates Demo')}. " \
             "AI-generated: a checklist, not a ruling. It never says whether a claim is true or whether to publish, " \
             "and it never writes the story._"
    lines << ""
    lines << "- **Label:** #{draft.label_name}"
    lines << "- **Beat:** #{draft.beat}" if draft.beat.present?
    lines << "- **Claims:** #{summary_line}"
    lines << ""
    lines << "## Claims"
    lines << ""
    if claims.empty?
      lines << "No factual claims found in the notes."
    else
      claims.each_with_index do |c, i|
        lines << "#{i + 1}. **#{self.class.state_name(c['state'])}**: #{c['claim']}"
        lines << "   - Source: #{c['source_name']}"
        lines << "   - To firm it up: #{c['how_to_firm_up']}"
      end
    end
    lines << ""
    lines << "## Affected but not heard"
    lines << ""
    affected_not_heard.each { |a| lines << "- #{a}" }
    lines << "Nobody obvious." if affected_not_heard.empty?
    lines << ""
    lines << "## Words that lean"
    lines << ""
    loaded_words.each { |w| lines << "- **#{w['word']}**: #{w['why']}" }
    lines << "None flagged." if loaded_words.empty?
    lines << ""
    lines << "## Questions to ask before you write"
    lines << ""
    questions_to_ask.each { |q| lines << "- #{q}" }
    lines << ""
    lines << "## Does the label fit?"
    lines << ""
    lines << label_fit.to_s
    lines << ""
    lines << "## Sources listed"
    lines << ""
    lines << (draft.sources? ? draft.sources_text.strip : "None yet.")
    lines.join("\n") + "\n"
  end

  def markdown_filename
    slug = story_draft.headline.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "").presence || "story"
    "#{slug}-source-check.md"
  end
end
