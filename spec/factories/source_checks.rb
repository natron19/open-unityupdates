FactoryBot.define do
  factory :source_check do
    association :story_draft
    status       { "pending" }
    generated_at { nil }
    gemini_raw   { nil }

    trait :completed do
      status       { "completed" }
      generated_at { Time.current }
      gemini_raw   { "{}" }
      claims do
        [
          { "claim" => "The pantry will close on Saturdays from October 4.", "state" => "sourced",
            "source_name" => "Pantry board letter to volunteers", "how_to_firm_up" => "Quote the date from the letter." },
          { "claim" => "Saturday visits fell to about 30 households a week.", "state" => "single_source",
            "source_name" => "Tomas Reyes", "how_to_firm_up" => "Ask for the sign-in sheets." },
          { "claim" => "The bus route changed in July.", "state" => "unsourced",
            "source_name" => "none", "how_to_firm_up" => "Check the transit authority's route notice." }
        ]
      end
      affected_not_heard { [ "Families who can only come on Saturdays" ] }
      loaded_words       { [ { "word" => "abandoned", "why" => "a judgement, not a fact" } ] }
      questions_to_ask   { [ "Who decided, and when?", "Were volunteers asked first?", "Is a weekday evening added instead?" ] }
      label_fit          { "Reported fits; two of three claims have a listed source." }
    end

    trait :failed do
      status         { "failed" }
      generated_at   { Time.current }
      gemini_raw     { "malformed response" }
      failure_reason { "JSON parse failed: unexpected token" }
    end
  end
end
