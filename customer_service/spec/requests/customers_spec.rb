require 'rails_helper'

RSpec.describe "Customers API", type: :request do
  describe "GET /customers/:id" do
    let!(:customer) { create(:customer, customer_name: "John Doe", address: "123 Main St, NY", orders_count: 5) }
    
    context "when the customer exists" do
      it "returns the customer" do
        get "/customers/#{customer.id}"
        
        expect(response).to have_http_status(:ok)
      end
      
      it "returns customer_name, address, and orders_count" do
        get "/customers/#{customer.id}"
        
        json_response = JSON.parse(response.body)
        
        expect(json_response).to include(
          'id' => customer.id,
          'customer_name' => 'John Doe',
          'address' => '123 Main St, NY',
          'orders_count' => 5
        )
      end
      
      it "returns all required fields" do
        get "/customers/#{customer.id}"
        
        json_response = JSON.parse(response.body)
        
        expect(json_response.keys).to match_array(['id', 'customer_name', 'address', 'orders_count'])
      end
      
      it "returns correct data types" do
        get "/customers/#{customer.id}"
        
        json_response = JSON.parse(response.body)
        
        expect(json_response['id']).to be_an(Integer)
        expect(json_response['customer_name']).to be_a(String)
        expect(json_response['address']).to be_a(String)
        expect(json_response['orders_count']).to be_an(Integer)
      end
    end
    
    context "when the customer does not exist" do
      it "returns 404 not found" do
        get "/customers/99999"
        
        expect(response).to have_http_status(:not_found)
      end
      
      it "returns error message" do
        get "/customers/99999"
        
        json_response = JSON.parse(response.body)
        
        expect(json_response['error']).to eq('Customer not found')
      end
    end
    
    context "when customer has no orders" do
      let!(:new_customer) { create(:customer, orders_count: 0) }
      
      it "returns orders_count as 0" do
        get "/customers/#{new_customer.id}"
        
        json_response = JSON.parse(response.body)
        
        expect(json_response['orders_count']).to eq(0)
      end
    end
    
    context "when customer has multiple orders" do
      let!(:active_customer) { create(:customer, orders_count: 25) }
      
      it "returns correct orders_count" do
        get "/customers/#{active_customer.id}"
        
        json_response = JSON.parse(response.body)
        
        expect(json_response['orders_count']).to eq(25)
      end
    end
    
    context "with invalid ID format" do
      it "returns 404 for non-numeric ID" do
        get "/customers/invalid"
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end
  
  describe "GET /health" do
    it "returns ok status" do
      get "/health"
      
      expect(response).to have_http_status(:ok)
      
      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('ok')
      expect(json_response['service']).to eq('customer_service')
    end
  end
end
