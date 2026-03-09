FactoryBot.define do
  factory :order do
    customer_id { 1 }
    product_name { Faker::Commerce.product_name }
    quantity { rand(1..10) }
    price { Faker::Commerce.price(range: 10.0..1000.0) }
    status { 'pending' }
    
    trait :confirmed do
      status { 'confirmed' }
    end
    
    trait :shipped do
      status { 'shipped' }
    end
    
    trait :delivered do
      status { 'delivered' }
    end
    
    trait :cancelled do
      status { 'cancelled' }
    end
    
    trait :with_specific_customer do
      transient do
        specific_customer_id { nil }
      end
      
      customer_id { specific_customer_id || 1 }
    end
  end
end
