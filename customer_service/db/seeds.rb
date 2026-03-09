# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "Seeding customers..."

customers_data = [
  {
    customer_name: "John Doe",
    address: "123 Main Street, New York, NY 10001, USA",
    orders_count: 0
  },
  {
    customer_name: "Jane Smith",
    address: "456 Oak Avenue, Los Angeles, CA 90001, USA",
    orders_count: 0
  },
  {
    customer_name: "Robert Johnson",
    address: "789 Pine Road, Chicago, IL 60601, USA",
    orders_count: 0
  },
  {
    customer_name: "Maria Garcia",
    address: "321 Elm Boulevard, Miami, FL 33101, USA",
    orders_count: 0
  },
  {
    customer_name: "David Chen",
    address: "654 Maple Drive, San Francisco, CA 94102, USA",
    orders_count: 0
  }
]

customers_data.each do |customer_attrs|
  Customer.find_or_create_by!(customer_name: customer_attrs[:customer_name]) do |customer|
    customer.address = customer_attrs[:address]
    customer.orders_count = customer_attrs[:orders_count]
  end
end

puts "Created #{Customer.count} customers"
