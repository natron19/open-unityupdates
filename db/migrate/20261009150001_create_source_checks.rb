class CreateSourceChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :source_checks, id: :uuid do |t|
      t.references :story_draft, type: :uuid, null: false, foreign_key: true
      t.string   :status, null: false, default: "pending"
      t.text     :gemini_raw
      t.string   :failure_reason
      t.datetime :generated_at

      t.jsonb :claims,             null: false, default: []
      t.jsonb :affected_not_heard, null: false, default: []
      t.jsonb :loaded_words,       null: false, default: []
      t.jsonb :questions_to_ask,   null: false, default: []
      t.text  :label_fit

      t.timestamps null: false
    end
    add_index :source_checks, :status
  end
end
