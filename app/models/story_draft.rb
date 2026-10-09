class StoryDraft < ApplicationRecord
  belongs_to :user
  has_many :source_checks, dependent: :destroy
  has_one :latest_source_check,
          -> { order(generated_at: :desc, created_at: :desc) },
          class_name: "SourceCheck"

  # The four plain-language labels every UnityUpdates story carries (brief §2).
  LABELS = %w[reported announcement opinion explainer].freeze

  LABEL_NAMES = {
    "reported"     => "Reported",
    "announcement" => "Announcement",
    "opinion"      => "Opinion",
    "explainer"    => "Explainer"
  }.freeze

  # Form option text.
  LABEL_OPTIONS = {
    "reported"     => "Reported: original reporting, with sources",
    "announcement" => "Announcement: news a group is sharing",
    "opinion"      => "Opinion: the writer's own view",
    "explainer"    => "Explainer: how something works or what it means"
  }.freeze

  # The phrase the AI template receives as {{label}}.
  LABEL_PROMPTS = {
    "reported"     => "reported (original reporting that should rest on sources)",
    "announcement" => "announcement (news a group or the organization is sharing about itself)",
    "opinion"      => "opinion (the writer's own view, which still rests on facts)",
    "explainer"    => "explainer (how something works or what it means, not a call to action)"
  }.freeze

  HEADLINE_MAX = 120
  BEAT_MAX     = 80
  NOTES_RANGE  = 30..3000
  SOURCES_MAX  = 1200

  validates :headline,     presence: true, length: { maximum: HEADLINE_MAX }
  validates :label,        presence: true, inclusion: { in: LABELS }
  validates :beat,         length: { maximum: BEAT_MAX }
  validates :notes,        presence: true, length: { in: NOTES_RANGE }
  validates :sources_text, length: { maximum: SOURCES_MAX }

  def label_name
    LABEL_NAMES.fetch(label, label.to_s.humanize)
  end

  def sources?
    sources_text.to_s.strip.present?
  end

  # Variables for the unityupdates_source_check_v1 template. Nothing about the user is sent.
  def ai_variables
    {
      headline:     headline,
      label:        LABEL_PROMPTS.fetch(label),
      beat:         beat.presence || "Not stated",
      sources_text: sources? ? sources_text.strip : "No sources listed yet.",
      notes:        notes
    }
  end

  # Everything the reporter typed. A person the AI names must appear somewhere in here (PersonNameCheck).
  def input_text
    [ headline, beat, notes, sources_text ].compact.join("\n")
  end
end
