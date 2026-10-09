require "rails_helper"

RSpec.describe "StoryDrafts", type: :request do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:draft) { create(:story_draft, user: user) }

  let(:valid_params) do
    { story_draft: { headline: "Library fines end in May", label: "announcement", beat: "",
                     notes: "The Harbor Lane library will stop charging late fines from May 1.",
                     sources_text: "Library board minutes, April (document)" } }
  end

  context "when not signed in" do
    it "redirects every page to sign in" do
      get story_drafts_path
      expect(response).to redirect_to(sign_in_path)
      get dashboard_path
      expect(response).to redirect_to(sign_in_path)
      post story_drafts_path, params: valid_params
      expect(response).to redirect_to(sign_in_path)
    end
  end

  context "when signed in" do
    before { sign_in_as(user) }

    it "shows the dashboard as My story drafts with only the user's own drafts" do
      create(:story_draft, user: user, headline: "Mine to check")
      create(:story_draft, user: other, headline: "Someone else's draft")
      get dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My story drafts", "Mine to check")
      expect(response.body).not_to include("Someone else&#39;s draft")
    end

    it "shows the latest check's summary on the dashboard" do
      create(:source_check, :completed, story_draft: draft)
      get story_drafts_path
      expect(response.body).to include("1 sourced · 1 single source · 1 unsourced")
    end

    it "shows an empty state with no drafts" do
      get story_drafts_path
      expect(response.body).to include("Start your first story draft")
    end

    it "renders the new form with the labels the UI journey fills" do
      get new_story_draft_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Working headline", "Label", "Beat", "Your reporting notes", "Sources", "Save draft")
      expect(response.body).to include(*StoryDraft::LABEL_OPTIONS.values.map { |o| ERB::Util.html_escape(o) })
    end

    it "creates a draft and redirects to it" do
      expect { post story_drafts_path, params: valid_params }.to change(user.story_drafts, :count).by(1)
      expect(response).to redirect_to(story_draft_path(StoryDraft.last))
    end

    it "re-renders the form with 422 on invalid input" do
      expect {
        post story_drafts_path, params: { story_draft: valid_params[:story_draft].merge(notes: "short") }
      }.not_to change(StoryDraft, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "shows the draft with its notes, sources and the Check sources button" do
      get story_draft_path(draft)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(draft.headline, "Reported", "Tomas Reyes, pantry coordinator", "Check sources")
    end

    it "says when a draft has no sources" do
      draft.update!(sources_text: "")
      get story_draft_path(draft)
      expect(response.body).to include("None listed yet")
    end

    it "updates a draft" do
      patch story_draft_path(draft), params: { story_draft: { headline: "A sharper headline" } }
      expect(response).to redirect_to(story_draft_path(draft))
      expect(draft.reload.headline).to eq("A sharper headline")
    end

    it "rejects an invalid update with 422" do
      patch story_draft_path(draft), params: { story_draft: { label: "rumour" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "deletes a draft" do
      draft
      expect { delete story_draft_path(draft) }.to change(StoryDraft, :count).by(-1)
      expect(response).to redirect_to(story_drafts_path)
    end
  end

  # open-base's ApplicationController answers RecordNotFound with a redirect to root and an alert.
  context "when signed in as a different user" do
    before { sign_in_as(other) }

    it "cannot see, edit, update, or delete the draft" do
      get story_draft_path(draft)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("That record could not be found.")
      get edit_story_draft_path(draft)
      expect(response).to redirect_to(root_path)
      patch story_draft_path(draft), params: { story_draft: { headline: "Hijacked" } }
      expect(response).to redirect_to(root_path)
      expect { delete story_draft_path(draft) }.not_to change(StoryDraft, :count)
      expect(response).to redirect_to(root_path)
      expect(draft.reload.headline).not_to eq("Hijacked")
    end
  end
end
