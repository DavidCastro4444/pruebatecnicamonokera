FactoryBot.define do
  factory :customer do
    customer_name { Faker::Name.name }
    address { "#{Faker::Address.street_address}, #{Faker::Address.city}, #{Faker::Address.state_abbr} #{Faker::Address.zip}, USA" }
    orders_count { 0 }
    
    trait :with_orders do
      orders_count { rand(1..10) }
    end
    
    trait :john_doe do
      customer_name { "John Doe" }
      address { "123 Main Street, New York, NY 10001, USA" }
    end
    
    trait :jane_smith do
      customer_name { "Jane Smith" }
      address { "456 Oak Avenue, Los Angeles, CA 90001, USA" }
    end
  end
end
