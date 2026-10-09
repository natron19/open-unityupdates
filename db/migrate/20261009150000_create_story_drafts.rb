class CreateStoryDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :story_drafts, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :headline,     null: false
      t.string :label,        null: false
      t.string :beat
      t.text   :notes,        null: false
      t.text   :sources_text

      t.timestamps null: false
    end
  end
end
