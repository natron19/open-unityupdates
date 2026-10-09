FactoryBot.define do
  factory :story_draft do
    association :user
    headline     { "Northgate Food Pantry cuts Saturday hours" }
    label        { "reported" }
    beat         { "The food pantry" }
    notes        { "The pantry will close on Saturdays from October 4. Tomas Reyes said Saturday visits fell to about 30 households a week." }
    sources_text { "Pantry board letter to volunteers, September 2 (document)\nTomas Reyes, pantry coordinator (interview)" }
  end
end
