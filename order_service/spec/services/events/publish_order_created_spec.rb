require 'rails_helper'

RSpec.describe Events::PublishOrderCreated do
  let(:order) { create(:order, customer_id: 1, product_name: "Laptop", quantity: 2, price: 999.99) }
  
  describe ".call" do
    let(:mock_connection) { instance_double(Bunny::Session) }
    let(:mock_channel) { instance_double(Bunny::Channel) }
    let(:mock_exchange) { instance_double(Bunny::Exchange) }
    
    before do
      # Mock Bunny connection chain
      allow(Bunny).to receive(:new).and_return(mock_connection)
      allow(mock_connection).to receive(:start).and_return(mock_connection)
      allow(mock_connection).to receive(:create_channel).and_return(mock_channel)
      allow(mock_channel).to receive(:topic).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)
    end
    
    it "publishes message to RabbitMQ exchange" do
      expect(mock_exchange).to receive(:publish).with(
        anything,
        hash_including(
          routing_key: 'order.created',
          persistent: true,
          content_type: 'application/json'
        )
      )
      
      described_class.call(order)
    end
    
    it "publishes event with correct payload structure" do
      published_payload = nil
      
      allow(mock_exchange).to receive(:publish) do |payload, _options|
        published_payload = JSON.parse(payload)
      end
      
      described_class.call(order)
      
      expect(published_payload).to include(
        'event_id',
        'occurred_at',
        'type',
        'order'
      )
    end
    
    it "includes event_id as UUID" do
      published_payload = nil
      
      allow(mock_exchange).to receive(:publish) do |payload, _options|
        published_payload = JSON.parse(payload)
      end
      
      described_class.call(order)
      
      expect(published_payload['event_id']).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
    end
    
    it "includes occurred_at as ISO8601 timestamp" do
      published_payload = nil
      
      allow(mock_exchange).to receive(:publish) do |payload, _options|
        published_payload = JSON.parse(payload)
      end
      
      described_class.call(order)
      
      expect(published_payload['occurred_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
    
    it "includes type as 'order.created.v1'" do
      published_payload = nil
      
      allow(mock_exchange).to receive(:publish) do |payload, _options|
        published_payload = JSON.parse(payload)
      end
      
      described_class.call(order)
      
      expect(published_payload['type']).to eq('order.created.v1')
    end
    
    it "includes order data with all required fields" do
      published_payload = nil
      
      allow(mock_exchange).to receive(:publish) do |payload, _options|
        published_payload = JSON.parse(payload)
      end
      
      described_class.call(order)
      
      expect(published_payload['order']).to include(
        'id' => order.id,
        'customer_id' => 1,
        'product_name' => 'Laptop',
        'quantity' => 2,
        'price' => '999.99',
        'status' => 'pending'
      )
    end
    
    it "formats price as string in payload" do
      published_payload = nil
      
      allow(mock_exchange).to receive(:publish) do |payload, _options|
        published_payload = JSON.parse(payload)
      end
      
      described_class.call(order)
      
      expect(published_payload['order']['price']).to be_a(String)
      expect(published_payload['order']['price']).to eq('999.99')
    end
    
    it "uses correct exchange name from ENV" do
      expect(mock_channel).to receive(:topic).with(
        ENV.fetch('ORDER_EVENTS_EXCHANGE', 'order.events'),
        durable: true
      )
      
      described_class.call(order)
    end
    
    it "publishes with persistent flag for durability" do
      expect(mock_exchange).to receive(:publish).with(
        anything,
        hash_including(persistent: true)
      )
      
      described_class.call(order)
    end
    
    it "publishes with timestamp" do
      expect(mock_exchange).to receive(:publish).with(
        anything,
        hash_including(timestamp: kind_of(Integer))
      )
      
      described_class.call(order)
    end
    
    it "logs successful publication" do
      expect(Rails.logger).to receive(:info).with(/Published order.created event for order #{order.id}/)
      
      described_class.call(order)
    end
    
    it "returns true on success" do
      result = described_class.call(order)
      
      expect(result).to be true
    end
  end
end
