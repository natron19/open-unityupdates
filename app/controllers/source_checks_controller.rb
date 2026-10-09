class SourceChecksController < ApplicationController
  TEMPLATE = "unityupdates_source_check_v1".freeze

  MAX_CLAIMS      = 15
  MAX_AFFECTED    = 5
  MAX_LOADED      = 6
  QUESTIONS       = 3..6
  MAX_CLAIM_CHARS = 500 # a claim is quoted from the notes, so it may be a long sentence
  MAX_LINE_CHARS  = 300 # every other field is one line

  before_action :set_story_draft

  rate_limit to: 10, within: 1.minute, only: :create, by: -> { current_user.id }

  # shared/_ai_error's "Try again" and a browser refresh after an error are GETs to this path; send them to the draft.
  def index
    redirect_to story_draft_path(@story_draft)
  end

  def show
    @source_check = @story_draft.source_checks.find(params[:id])
  end

  def create
    raw = GeminiService.generate(template: TEMPLATE, variables: @story_draft.ai_variables)

    @source_check = @story_draft.source_checks.create!(
      status:       "pending",
      gemini_raw:   raw,
      generated_at: Time.current
    )

    result = parse_source_check!(raw)
    @source_check.update!(result.merge(status: "completed"))
    redirect_to story_draft_source_check_path(@story_draft, @source_check)

  rescue ParseError => e
    @source_check.update!(status: "failed", failure_reason: e.message.truncate(250), gemini_raw: e.raw)
    redirect_to story_draft_source_check_path(@story_draft, @source_check)

  rescue GeminiService::BudgetExceededError
    render "shared/ai_error_page", locals: { error_type: :budget_exceeded }, status: :unprocessable_entity

  rescue GeminiService::GatekeeperError
    render "shared/ai_error_page", locals: { error_type: :gatekeeper_blocked }, status: :unprocessable_entity

  rescue GeminiService::OutputGuardError
    render "shared/ai_error_page", locals: { error_type: :output_blocked }, status: :unprocessable_entity

  rescue GeminiService::TimeoutError
    render "shared/ai_error_page", locals: { error_type: :timeout }, status: :unprocessable_entity

  rescue GeminiService::GeminiError
    render "shared/ai_error_page", locals: { error_type: :error }, status: :unprocessable_entity
  end

  private

  def set_story_draft
    @story_draft = current_user.story_drafts.find(params[:story_draft_id])
  end

  ParseError = Class.new(StandardError) do
    attr_reader :raw
    def initialize(msg, raw:)
      super(msg)
      @raw = raw
    end
  end

  # Validates the unityupdates_source_check_v1 JSON and returns the SourceCheck attributes.
  # Hard rules enforced here, not trusted to the model:
  #   - every claim state is sourced, single_source or unsourced;
  #   - every source named for a sourced or single_source claim is in the reporter's Sources box (SourceNameCheck);
  #   - no person name that is not in the reporter's input (PersonNameCheck);
  #   - 3 to 6 questions to ask;
  #   - every field is one line, never prose.
  def parse_source_check!(raw)
    fail_parse = ->(msg) { raise ParseError.new(msg, raw: raw) }

    stripped = raw.to_s.strip.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    parsed   = JSON.parse(stripped)
    fail_parse.("Expected a JSON object") unless parsed.is_a?(Hash)

    claims = parsed["claims"]
    fail_parse.("claims must be a list of 0-#{MAX_CLAIMS}") unless claims.is_a?(Array) && claims.size <= MAX_CLAIMS
    claims = claims.each_with_index.map do |claim, i|
      fail_parse.("Claim #{i + 1} is not an object") unless claim.is_a?(Hash)

      text  = one_line(claim["claim"], MAX_CLAIM_CHARS)
      fix   = one_line(claim["how_to_firm_up"], MAX_LINE_CHARS)
      state = claim["state"]
      name  = claim["source_name"]
      fail_parse.("Claim #{i + 1} is not one line of text") unless text
      fail_parse.("Claim #{i + 1} has no one-line how_to_firm_up") unless fix
      unless SourceCheck::CLAIM_STATES.include?(state)
        fail_parse.("Claim #{i + 1} has state #{state.to_s.truncate(30).inspect}, not sourced, single_source or unsourced")
      end
      fail_parse.("Claim #{i + 1} has no source_name") unless name.is_a?(String)

      if state == "unsourced"
        fail_parse.("Claim #{i + 1} is unsourced but names a source") unless SourceNameCheck.none?(name)
        name = "none"
      else
        fail_parse.("Claim #{i + 1} is #{state} but names no source") if SourceNameCheck.none?(name)
        name = name.strip
      end

      { "claim" => text, "state" => state, "source_name" => name, "how_to_firm_up" => fix }
    end

    unlisted = SourceNameCheck.unlisted(claims, @story_draft.sources_text)
    if unlisted.any?
      fail_parse.("The response cited a source that is not in your sources list (#{unlisted.first.truncate(60)})")
    end

    affected = line_list(parsed["affected_not_heard"])
    fail_parse.("affected_not_heard must be a list of 0-#{MAX_AFFECTED} one-line entries") unless affected && affected.size <= MAX_AFFECTED

    loaded = parsed["loaded_words"]
    unless loaded.is_a?(Array) && loaded.size <= MAX_LOADED &&
           loaded.all? { |w| w.is_a?(Hash) && one_line(w["word"], MAX_LINE_CHARS) && one_line(w["why"], MAX_LINE_CHARS) }
      fail_parse.("loaded_words must be a list of 0-#{MAX_LOADED} {word, why} entries")
    end
    loaded = loaded.map { |w| { "word" => w["word"].strip, "why" => w["why"].strip } }

    questions = line_list(parsed["questions_to_ask"])
    unless questions && QUESTIONS.cover?(questions.size)
      fail_parse.("Expected #{QUESTIONS.min}-#{QUESTIONS.max} questions_to_ask, got #{Array(parsed['questions_to_ask']).size}")
    end

    label_fit = one_line(parsed["label_fit"], MAX_LINE_CHARS)
    fail_parse.("label_fit must be one line") unless label_fit

    output_text = [
      *claims.flat_map { |c| [ c["claim"], c["source_name"], c["how_to_firm_up"] ] },
      *affected, *loaded.flat_map(&:values), *questions, label_fit
    ].join("\n")
    invented = PersonNameCheck.invented_in(output_text, @story_draft.input_text)
    if invented.any?
      fail_parse.("The response named a person who is not in your notes or sources (#{invented.first.truncate(60)})")
    end

    {
      claims:             claims,
      affected_not_heard: affected,
      loaded_words:       loaded,
      questions_to_ask:   questions,
      label_fit:          label_fit
    }
  rescue JSON::ParserError => e
    raise ParseError.new("JSON parse failed: #{e.message.truncate(120)}", raw: raw)
  end

  # A stripped, non-blank, single-line string of at most `max` characters; nil for anything else.
  def one_line(value, max)
    return nil unless value.is_a?(String)
    text = value.strip
    return nil if text.empty? || text.length > max || text.include?("\n")
    text
  end

  # An array of one-line strings, stripped; nil when the value is anything else.
  def line_list(value)
    return nil unless value.is_a?(Array)
    lines = value.map { |v| one_line(v, MAX_LINE_CHARS) }
    lines.all? ? lines : nil
  end
end
