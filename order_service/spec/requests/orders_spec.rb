require 'rails_helper'

RSpec.describe "Orders API", type: :request do
  describe "POST /orders" do
    let(:valid_attributes) do
      {
        order: {
          customer_id: 1,
          product_name: "Laptop Dell XPS 15",
          quantity: 2,
          price: 1299.99
        }
      }
    end
    
    let(:customer_service_response) do
      {
        id: 1,
        customer_name: "John Doe",
        email: "john@example.com",
        address: "123 Main Street, New York, NY 10001, USA"
      }
    end
    
    context "when the request is valid" do
      before do
        # Mock HTTP call to Customer Service
        stub_request(:get, "#{ENV.fetch('CUSTOMER_SERVICE_URL', 'http://localhost:3001')}/customers/1")
          .to_return(
            status: 200,
            body: customer_service_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        
        # Mock RabbitMQ event publishing
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "creates an order" do
        expect {
          post '/orders', params: valid_attributes, as: :json
        }.to change(Order, :count).by(1)
      end
      
      it "returns status 201 created" do
        post '/orders', params: valid_attributes, as: :json
        expect(response).to have_http_status(:created)
      end
      
      it "returns the created order with customer data" do
        post '/orders', params: valid_attributes, as: :json
        
        json_response = JSON.parse(response.body)
        
        expect(json_response).to include(
          'customer_id' => 1,
          'product_name' => 'Laptop Dell XPS 15',
          'quantity' => 2,
          'price' => '1299.99',
          'status' => 'pending'
        )
        
        expect(json_response['customer']).to include(
          'id' => 1,
          'name' => 'John Doe',
          'email' => 'john@example.com',
          'address' => '123 Main Street, New York, NY 10001, USA'
        )
      end
      
      it "publishes order.created event to RabbitMQ" do
        expect(Events::PublishOrderCreated).to receive(:call) do |order|
          expect(order).to be_a(Order)
          expect(order.customer_id).to eq(1)
          expect(order.product_name).to eq('Laptop Dell XPS 15')
        end
        
        post '/orders', params: valid_attributes, as: :json
      end
      
      it "makes HTTP request to Customer Service" do
        post '/orders', params: valid_attributes, as: :json
        
        expect(WebMock).to have_requested(:get, "#{ENV.fetch('CUSTOMER_SERVICE_URL', 'http://localhost:3001')}/customers/1")
          .once
      end
    end
    
    context "when Customer Service is unavailable" do
      before do
        # Mock Customer Service failure
        stub_request(:get, "#{ENV.fetch('CUSTOMER_SERVICE_URL', 'http://localhost:3001')}/customers/1")
          .to_timeout
        
        # Mock RabbitMQ event publishing
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "still creates the order" do
        expect {
          post '/orders', params: valid_attributes, as: :json
        }.to change(Order, :count).by(1)
      end
      
      it "returns 201 with customer as null" do
        post '/orders', params: valid_attributes, as: :json
        
        expect(response).to have_http_status(:created)
        
        json_response = JSON.parse(response.body)
        expect(json_response['customer']).to be_nil
      end
      
      it "includes a warning message" do
        post '/orders', params: valid_attributes, as: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response['warnings']).to include("Customer service unavailable. Customer data not included.")
      end
    end
    
    context "when RabbitMQ publishing fails" do
      before do
        # Mock Customer Service success
        stub_request(:get, "#{ENV.fetch('CUSTOMER_SERVICE_URL', 'http://localhost:3001')}/customers/1")
          .to_return(
            status: 200,
            body: customer_service_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        
        # Mock RabbitMQ failure
        allow(Events::PublishOrderCreated).to receive(:call).and_raise(StandardError.new("RabbitMQ connection failed"))
      end
      
      it "still creates the order and returns 201" do
        expect {
          post '/orders', params: valid_attributes, as: :json
        }.to change(Order, :count).by(1)
        
        expect(response).to have_http_status(:created)
      end
      
      it "logs the error but doesn't fail the request" do
        expect(Rails.logger).to receive(:error).with(/Failed to publish order.created event/)
        
        post '/orders', params: valid_attributes, as: :json
      end
    end
    
    context "when required fields are missing" do
      before do
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "returns 422 when customer_id is missing" do
        invalid_params = { order: valid_attributes[:order].except(:customer_id) }
        post '/orders', params: invalid_params, as: :json
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(/Customer/)
      end
      
      it "returns 422 when product_name is missing" do
        invalid_params = { order: valid_attributes[:order].except(:product_name) }
        post '/orders', params: invalid_params, as: :json
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(/Product name/)
      end
      
      it "returns 422 when quantity is missing" do
        invalid_params = { order: valid_attributes[:order].except(:quantity) }
        post '/orders', params: invalid_params, as: :json
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(/Quantity/)
      end
      
      it "returns 422 when price is missing" do
        invalid_params = { order: valid_attributes[:order].except(:price) }
        post '/orders', params: invalid_params, as: :json
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(/Price/)
      end
    end
    
    context "when quantity is invalid" do
      before do
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "returns 422 when quantity is zero" do
        invalid_params = { order: valid_attributes[:order].merge(quantity: 0) }
        post '/orders', params: invalid_params, as: :json
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(/Quantity must be greater than 0/)
      end
      
      it "returns 422 when quantity is negative" do
        invalid_params = { order: valid_attributes[:order].merge(quantity: -5) }
        post '/orders', params: invalid_params, as: :json
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(/Quantity must be greater than 0/)
      end
    end
    
    context "when price is invalid" do
      before do
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "returns 422 when price is negative" do
        invalid_params = { order: valid_attributes[:order].merge(price: -10.50) }
        post '/orders', params: invalid_params, as: :json
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to include(/Price must be greater than or equal to 0/)
      end
      
      it "accepts price of zero" do
        stub_request(:get, "#{ENV.fetch('CUSTOMER_SERVICE_URL', 'http://localhost:3001')}/customers/1")
          .to_return(
            status: 200,
            body: customer_service_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        
        valid_params = { order: valid_attributes[:order].merge(price: 0) }
        post '/orders', params: valid_params, as: :json
        
        expect(response).to have_http_status(:created)
      end
    end
  end
  
  describe "GET /orders" do
    let!(:customer_1_orders) do
      create_list(:order, 3, customer_id: 1)
    end
    
    let!(:customer_2_orders) do
      create_list(:order, 2, customer_id: 2)
    end
    
    context "when customer_id parameter is provided" do
      it "returns only orders for the specified customer" do
        get '/orders', params: { customer_id: 1 }
        
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(3)
        
        json_response.each do |order|
          expect(order['customer_id']).to eq(1)
        end
      end
      
      it "returns orders sorted by created_at descending" do
        get '/orders', params: { customer_id: 1 }
        
        json_response = JSON.parse(response.body)
        
        timestamps = json_response.map { |o| Time.parse(o['created_at']) }
        expect(timestamps).to eq(timestamps.sort.reverse)
      end
      
      it "returns empty array when customer has no orders" do
        get '/orders', params: { customer_id: 999 }
        
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end
      
      it "does not return orders from other customers" do
        get '/orders', params: { customer_id: 1 }
        
        json_response = JSON.parse(response.body)
        
        customer_2_order_ids = customer_2_orders.map(&:id)
        returned_order_ids = json_response.map { |o| o['id'] }
        
        expect(returned_order_ids & customer_2_order_ids).to be_empty
      end
    end
    
    context "when customer_id parameter is missing" do
      it "returns 400 bad request" do
        get '/orders'
        
        expect(response).to have_http_status(:bad_request)
      end
      
      it "returns error message" do
        get '/orders'
        
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('customer_id parameter is required')
      end
    end
    
    context "when customer_id is empty string" do
      it "returns 400 bad request" do
        get '/orders', params: { customer_id: '' }
        
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
