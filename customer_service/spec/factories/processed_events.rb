FactoryBot.define do
  factory :processed_event do
    event_id { SecureRandom.uuid }
    processed_at { Time.current }
    
    trait :old do
      processed_at { 1.day.ago }
    end
    
    trait :recent do
      processed_at { 5.minutes.ago }
    end
  end
end
