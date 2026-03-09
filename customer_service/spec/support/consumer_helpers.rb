# Helper methods for testing consumers without RabbitMQ

module ConsumerHelpers
  # Simulate processing a RabbitMQ message without actual connection
  def simulate_consumer_message(consumer, payload, options = {})
    delivery_info = double('delivery_info',
      delivery_tag: options[:delivery_tag] || rand(1..1000),
      routing_key: options[:routing_key] || 'order.created'
    )
    
    properties = double('properties',
      correlation_id: options[:correlation_id]
    )
    
    # Mock the channel for ACK/NACK
    mock_channel = double('channel')
    allow(mock_channel).to receive(:ack)
    allow(mock_channel).to receive(:nack)
    allow(consumer).to receive(:instance_variable_get).with(:@channel).and_return(mock_channel)
    
    consumer.send(:process_message, delivery_info, properties, payload)
    
    mock_channel
  end
  
  # Build a valid order.created event payload
  def build_order_created_event(customer_id:, event_id: nil, **order_attrs)
    {
      event_id: event_id || SecureRandom.uuid,
      occurred_at: Time.current.iso8601,
      type: 'order.created.v1',
      order: {
        id: order_attrs[:order_id] || rand(1..1000),
        customer_id: customer_id,
        product_name: order_attrs[:product_name] || 'Test Product',
        quantity: order_attrs[:quantity] || 1,
        price: order_attrs[:price] || '99.99',
        status: order_attrs[:status] || 'pending'
      }
    }.to_json
  end
end

RSpec.configure do |config|
  config.include ConsumerHelpers, type: :consumer
end
