class StoryDraftsController < ApplicationController
  before_action :set_story_draft, only: %i[show edit update destroy]

  def index
    @story_drafts = current_user.story_drafts.includes(:latest_source_check).order(created_at: :desc)
  end

  def show
    @source_checks = @story_draft.source_checks.order(created_at: :desc)
  end

  def new
    @story_draft = current_user.story_drafts.build(label: "reported")
  end

  def create
    @story_draft = current_user.story_drafts.build(story_draft_params)
    if @story_draft.save
      redirect_to @story_draft
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @story_draft.update(story_draft_params)
      redirect_to @story_draft
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @story_draft.destroy
    redirect_to story_drafts_path
  end

  private

  def set_story_draft
    @story_draft = current_user.story_drafts.find(params[:id])
  end

  def story_draft_params
    params.require(:story_draft).permit(:headline, :label, :beat, :notes, :sources_text)
  end
end
