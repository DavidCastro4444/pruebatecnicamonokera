require 'rails_helper'

RSpec.describe Orders::Create do
  let(:valid_params) do
    {
      customer_id: 1,
      product_name: "Laptop Dell XPS 15",
      quantity: 2,
      price: 1299.99
    }
  end
  
  let(:customer_service_response) do
    {
      id: 1,
      name: "John Doe",
      email: "john@example.com",
      address: "123 Main Street, New York, NY 10001, USA"
    }
  end
  
  describe ".call" do
    context "when all services are available" do
      before do
        # Mock Customer Service HTTP call
        allow(Customers::Client).to receive(:fetch).with(1).and_return(customer_service_response)
        
        # Mock RabbitMQ event publishing
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "creates an order successfully" do
        expect {
          described_class.call(valid_params)
        }.to change(Order, :count).by(1)
      end
      
      it "returns success with order data" do
        result = described_class.call(valid_params)
        
        expect(result[:success]).to be true
        expect(result[:data]).to include(
          customer_id: 1,
          product_name: "Laptop Dell XPS 15",
          quantity: 2,
          status: 'pending'
        )
      end
      
      it "includes customer data in response" do
        result = described_class.call(valid_params)
        
        expect(result[:data][:customer]).to eq(customer_service_response)
      end
      
      it "calls Customer Service to fetch customer data" do
        expect(Customers::Client).to receive(:fetch).with(1)
        
        described_class.call(valid_params)
      end
      
      it "publishes order.created event" do
        expect(Events::PublishOrderCreated).to receive(:call) do |order|
          expect(order).to be_a(Order)
          expect(order.customer_id).to eq(1)
          expect(order.product_name).to eq("Laptop Dell XPS 15")
          expect(order.quantity).to eq(2)
          expect(order.price).to eq(BigDecimal("1299.99"))
        end
        
        described_class.call(valid_params)
      end
      
      it "does not include warnings when everything succeeds" do
        result = described_class.call(valid_params)
        
        expect(result[:data][:warnings]).to be_nil
      end
    end
    
    context "when Customer Service fails" do
      before do
        # Mock Customer Service failure
        allow(Customers::Client).to receive(:fetch).and_raise(Customers::Client::TimeoutError.new("Connection timeout"))
        
        # Mock RabbitMQ event publishing
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "still creates the order" do
        expect {
          described_class.call(valid_params)
        }.to change(Order, :count).by(1)
      end
      
      it "returns success with customer as null" do
        result = described_class.call(valid_params)
        
        expect(result[:success]).to be true
        expect(result[:data][:customer]).to be_nil
      end
      
      it "includes warning message" do
        result = described_class.call(valid_params)
        
        expect(result[:data][:warnings]).to include("Customer service unavailable. Customer data not included.")
      end
      
      it "logs the error" do
        expect(Rails.logger).to receive(:warn).with(/Failed to fetch customer 1/)
        
        described_class.call(valid_params)
      end
    end
    
    context "when RabbitMQ publishing fails" do
      before do
        # Mock Customer Service success
        allow(Customers::Client).to receive(:fetch).with(1).and_return(customer_service_response)
        
        # Mock RabbitMQ failure
        allow(Events::PublishOrderCreated).to receive(:call).and_raise(StandardError.new("RabbitMQ connection failed"))
      end
      
      it "still creates the order and returns success" do
        result = described_class.call(valid_params)
        
        expect(result[:success]).to be true
        expect(Order.count).to eq(1)
      end
      
      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Failed to publish order.created event/)
        
        described_class.call(valid_params)
      end
      
      it "includes customer data despite RabbitMQ failure" do
        result = described_class.call(valid_params)
        
        expect(result[:data][:customer]).to eq(customer_service_response)
      end
    end
    
    context "when validation fails" do
      before do
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "returns failure when customer_id is missing" do
        invalid_params = valid_params.except(:customer_id)
        result = described_class.call(invalid_params)
        
        expect(result[:success]).to be false
        expect(result[:errors]).to include(/Customer/)
      end
      
      it "returns failure when product_name is missing" do
        invalid_params = valid_params.except(:product_name)
        result = described_class.call(invalid_params)
        
        expect(result[:success]).to be false
        expect(result[:errors]).to include(/Product name/)
      end
      
      it "returns failure when quantity is zero" do
        invalid_params = valid_params.merge(quantity: 0)
        result = described_class.call(invalid_params)
        
        expect(result[:success]).to be false
        expect(result[:errors]).to include(/Quantity must be greater than 0/)
      end
      
      it "returns failure when quantity is negative" do
        invalid_params = valid_params.merge(quantity: -5)
        result = described_class.call(invalid_params)
        
        expect(result[:success]).to be false
        expect(result[:errors]).to include(/Quantity must be greater than 0/)
      end
      
      it "returns failure when price is negative" do
        invalid_params = valid_params.merge(price: -100)
        result = described_class.call(invalid_params)
        
        expect(result[:success]).to be false
        expect(result[:errors]).to include(/Price must be greater than or equal to 0/)
      end
      
      it "does not create an order when validation fails" do
        invalid_params = valid_params.merge(quantity: -1)
        
        expect {
          described_class.call(invalid_params)
        }.not_to change(Order, :count)
      end
      
      it "does not call Customer Service when validation fails" do
        expect(Customers::Client).not_to receive(:fetch)
        
        invalid_params = valid_params.except(:customer_id)
        described_class.call(invalid_params)
      end
      
      it "does not publish event when validation fails" do
        expect(Events::PublishOrderCreated).not_to receive(:call)
        
        invalid_params = valid_params.merge(quantity: 0)
        described_class.call(invalid_params)
      end
    end
    
    context "when customer does not exist" do
      before do
        # Mock Customer Service returning 404
        allow(Customers::Client).to receive(:fetch).and_raise(Customers::Client::NotFoundError.new("Customer not found"))
        
        # Mock RabbitMQ event publishing
        allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
      end
      
      it "still creates the order (resilient design)" do
        expect {
          described_class.call(valid_params)
        }.to change(Order, :count).by(1)
      end
      
      it "returns success with customer as null" do
        result = described_class.call(valid_params)
        
        expect(result[:success]).to be true
        expect(result[:data][:customer]).to be_nil
      end
      
      it "includes warning about customer not found" do
        result = described_class.call(valid_params)
        
        expect(result[:data][:warnings]).to include("Customer service unavailable. Customer data not included.")
      end
    end
  end
  
  describe "event payload structure" do
    before do
      allow(Customers::Client).to receive(:fetch).with(1).and_return(customer_service_response)
    end
    
    it "publishes event with correct structure" do
      expect(Events::PublishOrderCreated).to receive(:call) do |order|
        # Verify the order object has all required fields for the event
        expect(order.id).to be_present
        expect(order.customer_id).to eq(1)
        expect(order.product_name).to eq("Laptop Dell XPS 15")
        expect(order.quantity).to eq(2)
        expect(order.price).to be_a(BigDecimal)
        expect(order.status).to eq('pending')
      end
      
      described_class.call(valid_params)
    end
  end
  
  describe "response structure" do
    before do
      allow(Customers::Client).to receive(:fetch).with(1).and_return(customer_service_response)
      allow(Events::PublishOrderCreated).to receive(:call).and_return(true)
    end
    
    it "includes all required fields in response" do
      result = described_class.call(valid_params)
      
      expect(result[:data]).to include(
        :id,
        :customer_id,
        :product_name,
        :quantity,
        :price,
        :status,
        :created_at,
        :updated_at,
        :customer
      )
    end
    
    it "formats price as string" do
      result = described_class.call(valid_params)
      
      expect(result[:data][:price]).to be_a(String)
      expect(result[:data][:price]).to eq("1299.99")
    end
    
    it "formats timestamps as ISO8601" do
      result = described_class.call(valid_params)
      
      expect(result[:data][:created_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(result[:data][:updated_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end
end
