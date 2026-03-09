require 'rails_helper'

RSpec.describe OrderCreatedConsumer do
  let(:consumer) { described_class.new }
  let(:event_id) { SecureRandom.uuid }
  let(:correlation_id) { SecureRandom.uuid }
  
  let(:valid_event_payload) do
    {
      event_id: event_id,
      occurred_at: Time.current.iso8601,
      type: 'order.created.v1',
      order: {
        id: 1,
        customer_id: customer.id,
        product_name: 'Laptop',
        quantity: 2,
        price: '999.99',
        status: 'pending'
      }
    }.to_json
  end
  
  let(:customer) { create(:customer, orders_count: 0) }
  
  # Mock RabbitMQ objects
  let(:mock_delivery_info) { double('delivery_info', delivery_tag: 123, routing_key: 'order.created') }
  let(:mock_properties) { double('properties', correlation_id: correlation_id) }
  let(:mock_channel) { double('channel') }
  
  before do
    # Mock RabbitMQ channel for ACK/NACK operations
    allow(consumer).to receive(:instance_variable_get).with(:@channel).and_return(mock_channel)
    allow(mock_channel).to receive(:ack)
    allow(mock_channel).to receive(:nack)
  end
  
  describe "#process_message" do
    context "when processing a valid event" do
      it "increments the customer's orders_count" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        }.to change { customer.reload.orders_count }.from(0).to(1)
      end
      
      it "creates a processed_event record" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        }.to change(ProcessedEvent, :count).by(1)
      end
      
      it "stores the correct event_id in processed_events" do
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        
        processed_event = ProcessedEvent.find_by(event_id: event_id)
        expect(processed_event).to be_present
        expect(processed_event.event_id).to eq(event_id)
      end
      
      it "acknowledges the message" do
        expect(mock_channel).to receive(:ack).with(123)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
      end
      
      it "logs the successful processing" do
        expect(Rails.logger).to receive(:info).with(/Updated customer #{customer.id}: orders_count = 1/)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
      end
    end
    
    context "idempotency - when the same event is processed twice" do
      before do
        # Process the event once
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
      end
      
      it "does not increment orders_count again" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        }.not_to change { customer.reload.orders_count }
      end
      
      it "does not create another processed_event record" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        }.not_to change(ProcessedEvent, :count)
      end
      
      it "still acknowledges the message" do
        expect(mock_channel).to receive(:ack).with(123)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
      end
      
      it "logs that the event was already processed" do
        expect(Rails.logger).to receive(:info).with(/Event #{event_id} already processed, skipping/)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
      end
    end
    
    context "when customer does not exist" do
      let(:nonexistent_customer_payload) do
        {
          event_id: event_id,
          occurred_at: Time.current.iso8601,
          type: 'order.created.v1',
          order: {
            id: 1,
            customer_id: 99999,
            product_name: 'Laptop',
            quantity: 2,
            price: '999.99',
            status: 'pending'
          }
        }.to_json
      end
      
      # Criterio de diseño: Customer no existe => Error permanente => Dead Letter Queue
      # Justificación:
      # - No creamos customers automáticamente porque el Customer Service es el owner de ese recurso
      # - No ignoramos silenciosamente porque queremos visibilidad del problema
      # - Enviamos a DLQ para análisis posterior y posible re-procesamiento manual
      # - Loggeamos el error para alertas y monitoreo
      
      it "does not create a processed_event record" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, nonexistent_customer_payload)
        }.not_to change(ProcessedEvent, :count)
      end
      
      it "sends NACK without requeue (to Dead Letter Queue)" do
        expect(mock_channel).to receive(:nack).with(123, false, false)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, nonexistent_customer_payload)
      end
      
      it "logs the error as permanent" do
        expect(Rails.logger).to receive(:error).with(/Permanent error: ActiveRecord::RecordNotFound/)
        expect(Rails.logger).to receive(:error).with(/Sending to Dead Letter Queue/)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, nonexistent_customer_payload)
      end
      
      it "does not increment any customer's orders_count" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, nonexistent_customer_payload)
        }.not_to change { Customer.sum(:orders_count) }
      end
    end
    
    context "when payload is invalid JSON" do
      let(:invalid_json_payload) { "{ invalid json" }
      
      it "sends NACK without requeue (permanent error)" do
        expect(mock_channel).to receive(:nack).with(123, false, false)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, invalid_json_payload)
      end
      
      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Permanent error: JSON::ParserError/)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, invalid_json_payload)
      end
      
      it "does not create a processed_event" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, invalid_json_payload)
        }.not_to change(ProcessedEvent, :count)
      end
    end
    
    context "when payload is missing customer_id" do
      let(:missing_customer_id_payload) do
        {
          event_id: event_id,
          occurred_at: Time.current.iso8601,
          type: 'order.created.v1',
          order: {
            id: 1,
            product_name: 'Laptop',
            quantity: 2,
            price: '999.99',
            status: 'pending'
          }
        }.to_json
      end
      
      it "sends NACK without requeue" do
        expect(mock_channel).to receive(:nack).with(123, false, false)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, missing_customer_id_payload)
      end
      
      it "does not create a processed_event" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, missing_customer_id_payload)
        }.not_to change(ProcessedEvent, :count)
      end
    end
    
    context "when database connection fails (temporary error)" do
      before do
        # Simulate temporary database error
        allow(ProcessedEvent).to receive(:create!).and_raise(ActiveRecord::ConnectionTimeoutError.new("Connection timeout"))
      end
      
      it "sends NACK with requeue" do
        expect(mock_channel).to receive(:nack).with(123, false, true)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
      end
      
      it "logs the temporary error" do
        expect(Rails.logger).to receive(:warn).with(/Temporary error: ActiveRecord::ConnectionTimeoutError/)
        expect(Rails.logger).to receive(:warn).with(/Requeuing message for retry/)
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
      end
      
      it "does not increment orders_count" do
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        }.not_to change { customer.reload.orders_count }
      end
    end
    
    context "correlation_id extraction" do
      context "when correlation_id is in headers" do
        it "uses correlation_id from headers" do
          expect(Rails.logger).to receive(:info).with(/\[#{correlation_id}\] Received message/)
          
          consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        end
      end
      
      context "when correlation_id is not in headers" do
        let(:mock_properties_no_correlation) { double('properties', correlation_id: nil) }
        
        it "uses event_id as correlation_id" do
          expect(Rails.logger).to receive(:info).with(/\[#{event_id}\] Received message/)
          
          consumer.send(:process_message, mock_delivery_info, mock_properties_no_correlation, valid_event_payload)
        end
      end
    end
    
    context "transaction atomicity" do
      it "creates processed_event and increments orders_count in the same transaction" do
        # If either fails, both should rollback
        expect(ActiveRecord::Base).to receive(:transaction).and_call_original
        
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        
        # Verify both operations succeeded
        expect(ProcessedEvent.exists?(event_id: event_id)).to be true
        expect(customer.reload.orders_count).to eq(1)
      end
      
      it "rolls back both operations if processed_event creation fails after orders_count increment" do
        # This tests the transaction rollback behavior
        allow(ProcessedEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new)
        
        expect {
          consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        }.not_to change { customer.reload.orders_count }
      end
    end
    
    context "multiple events for the same customer" do
      let(:event_id_2) { SecureRandom.uuid }
      let(:second_event_payload) do
        {
          event_id: event_id_2,
          occurred_at: Time.current.iso8601,
          type: 'order.created.v1',
          order: {
            id: 2,
            customer_id: customer.id,
            product_name: 'Mouse',
            quantity: 1,
            price: '29.99',
            status: 'pending'
          }
        }.to_json
      end
      
      it "increments orders_count for each unique event" do
        # First event
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        expect(customer.reload.orders_count).to eq(1)
        
        # Second event
        consumer.send(:process_message, mock_delivery_info, mock_properties, second_event_payload)
        expect(customer.reload.orders_count).to eq(2)
      end
      
      it "creates separate processed_event records" do
        consumer.send(:process_message, mock_delivery_info, mock_properties, valid_event_payload)
        consumer.send(:process_message, mock_delivery_info, mock_properties, second_event_payload)
        
        expect(ProcessedEvent.count).to eq(2)
        expect(ProcessedEvent.pluck(:event_id)).to match_array([event_id, event_id_2])
      end
    end
  end
  
  describe "error classification" do
    it "classifies RecordNotFound as permanent error" do
      expect(described_class::PERMANENT_ERRORS).to include(ActiveRecord::RecordNotFound)
    end
    
    it "classifies JSON::ParserError as permanent error" do
      expect(described_class::PERMANENT_ERRORS).to include(JSON::ParserError)
    end
    
    it "classifies ConnectionTimeoutError as temporary error" do
      expect(described_class::TEMPORARY_ERRORS).to include(ActiveRecord::ConnectionTimeoutError)
    end
    
    it "classifies ConnectionNotEstablished as temporary error" do
      expect(described_class::TEMPORARY_ERRORS).to include(ActiveRecord::ConnectionNotEstablished)
    end
  end
end
