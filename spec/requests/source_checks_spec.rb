require "rails_helper"

RSpec.describe "SourceChecks", type: :request do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:draft) { create(:story_draft, user: user) }

  let(:result) do
    {
      "claims" => [
        { "claim" => "The pantry will close on Saturdays from October 4.", "state" => "sourced",
          "source_name" => "Pantry board letter to volunteers, September 2", "how_to_firm_up" => "Quote the date from the letter." },
        { "claim" => "Saturday visits fell to about 30 households a week.", "state" => "single_source",
          "source_name" => "Tomas Reyes", "how_to_firm_up" => "Ask Tomas Reyes for the sign-in sheets." },
        { "claim" => "The bus route changed in July.", "state" => "unsourced",
          "source_name" => "none", "how_to_firm_up" => "Check the transit authority's route notice." }
      ],
      "affected_not_heard" => [ "Families who can only come on Saturdays" ],
      "loaded_words"       => [ { "word" => "abandoned", "why" => "a judgement, not a fact" } ],
      "questions_to_ask"   => [ "Who decided, and when?", "Were volunteers asked first?", "Is a weekday evening added instead?" ],
      "label_fit"          => "Reported fits; two of three claims have a listed source."
    }
  end

  def with_claim(index, changes)
    result.deep_dup.tap { |r| r["claims"][index].merge!(changes) }
  end

  def run_check
    post story_draft_source_checks_path(draft)
  end

  describe "POST /drafts/:story_draft_id/checks" do
    context "when not signed in" do
      it "redirects to sign in" do
        run_check
        expect(response).to redirect_to(sign_in_path)
      end
    end

    context "when signed in as the owner with a valid response" do
      before do
        sign_in_as(user)
        gemini_returns(result.to_json)
      end

      it "calls GeminiService with the template and the draft's variables" do
        expect(GeminiService).to receive(:generate).with(
          template:  "unityupdates_source_check_v1",
          variables: {
            headline:     draft.headline,
            label:        StoryDraft::LABEL_PROMPTS["reported"],
            beat:         draft.beat,
            sources_text: draft.sources_text,
            notes:        draft.notes
          }
        ).and_return(result.to_json)
        run_check
      end

      it "creates a completed check with the parsed fields and the raw response" do
        expect { run_check }.to change(SourceCheck, :count).by(1)
        check = SourceCheck.last
        expect(check.status).to eq("completed")
        expect(check.gemini_raw).to eq(result.to_json)
        expect(check.claims).to eq(result["claims"])
        expect(check.questions_to_ask.size).to eq(3)
        expect(check.label_fit).to eq(result["label_fit"])
        expect(check.generated_at).to be_present
      end

      it "redirects to the result page" do
        run_check
        expect(response).to redirect_to(story_draft_source_check_path(draft, SourceCheck.last))
      end

      it "accepts a response wrapped in a ```json fence" do
        gemini_returns("```json\n#{result.to_json}\n```")
        run_check
        expect(SourceCheck.last.status).to eq("completed")
      end

      it "accepts a claim backed by two listed sources" do
        gemini_returns(with_claim(0, "source_name" => "Pantry board letter to volunteers; Tomas Reyes").to_json)
        run_check
        expect(SourceCheck.last.status).to eq("completed")
      end

      it "stores an unsourced claim's blank source as none" do
        gemini_returns(with_claim(2, "source_name" => "").to_json)
        run_check
        expect(SourceCheck.last.claims.last["source_name"]).to eq("none")
      end

      it "accepts notes with no factual claims" do
        gemini_returns(result.merge("claims" => [], "loaded_words" => [], "affected_not_heard" => []).to_json)
        run_check
        expect(SourceCheck.last.status).to eq("completed")
      end

      it "marks every claim unsourced when the draft lists no sources" do
        draft.update!(sources_text: "")
        unsourced = result.deep_dup.tap { |r| r["claims"].each { |c| c.merge!("state" => "unsourced", "source_name" => "none") } }
        gemini_returns(unsourced.to_json)
        run_check
        expect(SourceCheck.last.status).to eq("completed")
      end
    end

    context "when the response cannot be used" do
      before { sign_in_as(user) }

      {
        "is not JSON"                                => "this is not json at all",
        "is a JSON array"                            => "[1, 2]",
        "has no claims list"                         => :no_claims,
        "has sixteen claims"                         => :too_many_claims,
        "has a claim that is not an object"          => :claim_string,
        "has a claim with no how_to_firm_up"         => :no_fix,
        "has a sourced claim with no source"         => :sourced_none,
        "has an unsourced claim that names a source" => :unsourced_named,
        "has six affected_not_heard entries"         => :too_many_affected,
        "has a loaded word without a why"            => :loaded_no_why,
        "has two questions_to_ask"                   => :two_questions,
        "has seven questions_to_ask"                 => :seven_questions,
        "has a blank label_fit"                      => :blank_label_fit
      }.each do |description, raw|
        it "marks the check failed and keeps the raw text when the response #{description}" do
          text = case raw
          when :no_claims         then result.except("claims").to_json
          when :too_many_claims   then result.merge("claims" => Array.new(16) { result["claims"].last }).to_json
          when :claim_string      then result.merge("claims" => [ "The pantry closes on Saturdays." ]).to_json
          when :no_fix            then with_claim(0, "how_to_firm_up" => " ").to_json
          when :sourced_none      then with_claim(0, "source_name" => "none").to_json
          when :unsourced_named   then with_claim(2, "source_name" => "Tomas Reyes").to_json
          when :too_many_affected then result.merge("affected_not_heard" => Array.new(6) { |i| "Group #{i}" }).to_json
          when :loaded_no_why     then result.merge("loaded_words" => [ { "word" => "abandoned" } ]).to_json
          when :two_questions     then result.merge("questions_to_ask" => result["questions_to_ask"].first(2)).to_json
          when :seven_questions   then result.merge("questions_to_ask" => Array.new(7) { |i| "Question #{i}?" }).to_json
          when :blank_label_fit   then result.merge("label_fit" => "").to_json
          else raw
          end
          gemini_returns(text)

          expect { run_check }.to change(SourceCheck, :count).by(1)
          check = SourceCheck.last
          expect(check.status).to eq("failed")
          expect(check.gemini_raw).to eq(text)
          expect(check.failure_reason).to be_present
          expect(response).to redirect_to(story_draft_source_check_path(draft, check))
        end
      end

      # Hard rule: claim state in the enum (production's SOURCE_CHECK_SCHEMA enum).
      it "fails a claim state outside sourced, single_source and unsourced" do
        gemini_returns(with_claim(0, "state" => "verified").to_json)
        run_check
        check = SourceCheck.last
        expect(check.status).to eq("failed")
        expect(check.failure_reason).to include('state "verified"', "not sourced, single_source or unsourced")
      end

      # Hard rule: never invents a source (SourceNameCheck).
      it "fails a sourced claim that cites a source not in the reporter's list, and says why on the page" do
        gemini_returns(with_claim(0, "source_name" => "County records").to_json)
        run_check
        check = SourceCheck.last
        expect(check.status).to eq("failed")
        expect(check.failure_reason).to include("not in your sources list", "County records")

        follow_redirect!
        expect(response.body).to include("could not be used", "not in your sources list", "Retry", "County records")
        expect(response.body).not_to include("Download .md")
      end

      it "fails a single_source claim when the draft lists no sources at all" do
        draft.update!(sources_text: "")
        gemini_returns(result.to_json)
        run_check
        expect(SourceCheck.last.failure_reason).to include("not in your sources list")
      end

      # Hard rule: never names a person who is not in the notes (PersonNameCheck).
      it "fails a response that names a person who is not in the notes or sources" do
        gemini_returns(result.merge("questions_to_ask" => result["questions_to_ask"] + [ "Did Councillor Brannigan vote for it?" ]).to_json)
        run_check
        check = SourceCheck.last
        expect(check.status).to eq("failed")
        expect(check.failure_reason).to include("named a person who is not in your notes or sources", "Brannigan")
      end

      it "fails an invented full name in any field" do
        gemini_returns(with_claim(2, "how_to_firm_up" => "Ask Dana Whitlock at the transit office.").to_json)
        run_check
        expect(SourceCheck.last.failure_reason).to include("Dana Whitlock")
      end

      it "completes when the only person named is in the notes" do
        gemini_returns(result.to_json) # "Ask Tomas Reyes for the sign-in sheets." names a listed source
        run_check
        expect(SourceCheck.last.status).to eq("completed")
      end

      # Hard rule: the AI never writes story prose; every field is one line.
      it "fails a field that is more than one line" do
        gemini_returns(result.merge("label_fit" => "On a crisp autumn morning, the pantry fell quiet.\n\nVolunteers wept.").to_json)
        run_check
        expect(SourceCheck.last.failure_reason).to eq("label_fit must be one line")
      end

      it "fails a claim longer than 500 characters" do
        gemini_returns(with_claim(0, "claim" => "x" * 501).to_json)
        run_check
        expect(SourceCheck.last.failure_reason).to include("Claim 1 is not one line of text")
      end
    end

    context "when GeminiService raises" do
      before { sign_in_as(user) }

      {
        GeminiService::BudgetExceededError => "daily AI request limit",
        GeminiService::GatekeeperError     => "couldn't be processed",
        GeminiService::OutputGuardError    => "didn't pass our safety checks",
        GeminiService::TimeoutError        => "took too long",
        GeminiService::GeminiError         => "An unexpected error occurred"
      }.each do |error_class, message|
        it "renders the #{error_class.name.demodulize} message with 422 and creates no check" do
          gemini_raises(error_class)
          expect { run_check }.not_to change(SourceCheck, :count)
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include(message)
        end
      end
    end

    # open-base's ApplicationController answers RecordNotFound with a redirect to root and an alert.
    context "when signed in as a different user" do
      it "does not find the draft, calls no AI, and creates no check" do
        sign_in_as(other)
        expect(GeminiService).not_to receive(:generate)
        expect { run_check }.not_to change(SourceCheck, :count)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("That record could not be found.")
      end
    end

    context "rate limit" do
      it "refuses the 11th check within a minute" do
        sign_in_as(user)
        gemini_returns(result.to_json)
        10.times { run_check }
        expect(response).to have_http_status(:redirect)
        run_check
        expect(response).to have_http_status(:too_many_requests)
        expect(SourceCheck.count).to eq(10)
      end
    end
  end

  describe "GET /drafts/:story_draft_id/checks (the error page's Try again)" do
    it "redirects to the draft" do
      sign_in_as(user)
      get story_draft_source_checks_path(draft)
      expect(response).to redirect_to(story_draft_path(draft))
    end
  end

  describe "GET /drafts/:story_draft_id/checks/:id" do
    context "for a completed check" do
      let(:check) { create(:source_check, :completed, story_draft: draft, generated_at: 1.minute.from_now) }

      it "shows the claims, the second read, the actions, and the disclaimer" do
        sign_in_as(user)
        get story_draft_source_check_path(draft, check)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(
          "Claims", "1 sourced · 1 single source · 1 unsourced", check.claims.first["claim"],
          "Sourced", "Single source", "Unsourced", "Tomas Reyes", "the transit authority&#39;s route notice",
          "Affected but not heard", check.affected_not_heard.first, "Words that lean", "abandoned",
          "Questions to ask before you write", check.questions_to_ask.last, "Does the label fit?", check.label_fit,
          "Download .md", "Show raw response", "AI-generated.", "never writes the story"
        )
        expect(response.body).not_to include("Your notes have changed")
      end
    end

    it "shows empty states for a check with no claims or flags" do
      check = create(:source_check, :completed, story_draft: draft, claims: [], affected_not_heard: [], loaded_words: [])
      sign_in_as(user)
      get story_draft_source_check_path(draft, check)
      expect(response.body).to include("No factual claims found in the notes.", "Nobody obvious.", "None flagged.")
    end

    context "for a failed check" do
      it "shows the reason, Retry, and the raw response, with no download" do
        check = create(:source_check, :failed, story_draft: draft)
        sign_in_as(user)
        get story_draft_source_check_path(draft, check)
        expect(response.body).to include("could not be used", check.failure_reason, "Retry", "malformed response")
        expect(response.body).not_to include("Download .md")
      end
    end

    it "warns when the notes changed after the check" do
      check = create(:source_check, :completed, story_draft: draft, generated_at: 1.hour.ago)
      draft.update!(headline: "A newer headline")
      sign_in_as(user)
      get story_draft_source_check_path(draft, check)
      expect(response.body).to include("Your notes have changed since this check")
    end

    it "does not show another user's check" do
      check = create(:source_check, :completed, story_draft: draft)
      sign_in_as(other)
      get story_draft_source_check_path(draft, check)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("That record could not be found.")
    end

    it "does not show a check under a different draft of the same user" do
      check = create(:source_check, :completed, story_draft: draft)
      sign_in_as(user)
      get story_draft_source_check_path(create(:story_draft, user: user), check)
      expect(response).to redirect_to(root_path)
    end
  end
end
