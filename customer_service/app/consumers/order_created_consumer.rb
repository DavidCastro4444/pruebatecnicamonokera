class OrderCreatedConsumer
  TEMPORARY_ERRORS = [
    ActiveRecord::ConnectionTimeoutError,
    ActiveRecord::ConnectionNotEstablished,
    PG::ConnectionBad,
    PG::UnableToSend
  ].freeze
  
  PERMANENT_ERRORS = [
    ActiveRecord::RecordNotFound,
    ActiveRecord::RecordInvalid,
    JSON::ParserError
  ].freeze
  
  def self.start
    new.start
  end
  
  def initialize
    @connection = RabbitMQClient.connection
    @channel = RabbitMQClient.channel
    @queue = RabbitMQClient.order_created_queue
    
    @channel.prefetch(1)
    setup_signal_handlers
  end
  
  def start
    Rails.logger.info "[OrderCreatedConsumer] Starting consumer..."
    Rails.logger.info "[OrderCreatedConsumer] Listening on queue: #{@queue.name}"
    
    @queue.subscribe(manual_ack: true, block: true) do |delivery_info, properties, payload|
      process_message(delivery_info, properties, payload)
    end
  rescue Interrupt
    Rails.logger.info "[OrderCreatedConsumer] Shutting down gracefully..."
    shutdown
  end
  
  private
  
  def process_message(delivery_info, properties, payload)
    correlation_id = extract_correlation_id(properties, payload)
    Rails.logger.info "[OrderCreatedConsumer] [#{correlation_id}] Received message"
    
    event_data = parse_payload(payload)
    event_id = event_data['event_id']
    Rails.logger.info "[OrderCreatedConsumer] [#{correlation_id}] Event ID: #{event_id}"
    
    process_with_idempotency(event_data, correlation_id)
    
    @channel.ack(delivery_info.delivery_tag)
    Rails.logger.info "[OrderCreatedConsumer] [#{correlation_id}] Message acknowledged"
    
  rescue *TEMPORARY_ERRORS => e
    handle_temporary_error(e, delivery_info, correlation_id)
  rescue *PERMANENT_ERRORS => e
    handle_permanent_error(e, delivery_info, correlation_id, payload)
  rescue StandardError => e
    handle_unknown_error(e, delivery_info, correlation_id, payload)
  end
  
  def extract_correlation_id(properties, payload)
    return properties.correlation_id if properties.correlation_id.present?
    
    event_data = JSON.parse(payload)
    event_data['event_id'] || SecureRandom.uuid
  rescue JSON::ParserError
    SecureRandom.uuid
  end
  
  def parse_payload(payload)
    JSON.parse(payload)
  rescue JSON::ParserError => e
    Rails.logger.error "[OrderCreatedConsumer] Invalid JSON payload: #{e.message}"
    raise
  end
  
  def process_with_idempotency(event_data, correlation_id)
    event_id = event_data['event_id']
    customer_id = event_data.dig('order', 'customer_id')
    
    raise ArgumentError, "Missing customer_id in event payload" unless customer_id
    
    ActiveRecord::Base.transaction do
      return if event_already_processed?(event_id, correlation_id)
      
      create_processed_event(event_id)
      increment_customer_orders(customer_id, correlation_id)
    end
  end
  
  def event_already_processed?(event_id, correlation_id)
    ProcessedEvent.create!(event_id: event_id, processed_at: Time.current)
    false
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info "[OrderCreatedConsumer] [#{correlation_id}] Event #{event_id} already processed, skipping"
    true
  end
  
  def create_processed_event(event_id)
    ProcessedEvent.create!(event_id: event_id, processed_at: Time.current)
  end
  
  def increment_customer_orders(customer_id, correlation_id)
    customer = Customer.find(customer_id)
    customer.increment!(:orders_count)
    Rails.logger.info "[OrderCreatedConsumer] [#{correlation_id}] Updated customer #{customer_id}: orders_count = #{customer.orders_count}"
  end
  
  def handle_temporary_error(error, delivery_info, correlation_id)
    Rails.logger.warn "[OrderCreatedConsumer] [#{correlation_id}] Temporary error: #{error.class} - #{error.message}"
    Rails.logger.warn "[OrderCreatedConsumer] [#{correlation_id}] Requeuing message for retry"
    @channel.nack(delivery_info.delivery_tag, false, true)
  end
  
  def handle_permanent_error(error, delivery_info, correlation_id, payload)
    Rails.logger.error "[OrderCreatedConsumer] [#{correlation_id}] Permanent error: #{error.class} - #{error.message}"
    Rails.logger.error "[OrderCreatedConsumer] [#{correlation_id}] Payload: #{payload}"
    Rails.logger.error "[OrderCreatedConsumer] [#{correlation_id}] Sending to Dead Letter Queue"
    @channel.nack(delivery_info.delivery_tag, false, false)
  end
  
  def handle_unknown_error(error, delivery_info, correlation_id, payload)
    Rails.logger.error "[OrderCreatedConsumer] [#{correlation_id}] Unknown error: #{error.class} - #{error.message}"
    Rails.logger.error "[OrderCreatedConsumer] [#{correlation_id}] Backtrace: #{error.backtrace.first(5).join("\n")}"
    Rails.logger.error "[OrderCreatedConsumer] [#{correlation_id}] Payload: #{payload}"
    Rails.logger.warn "[OrderCreatedConsumer] [#{correlation_id}] Requeuing message (unknown error)"
    @channel.nack(delivery_info.delivery_tag, false, true)
  end
  
  def setup_signal_handlers
    Signal.trap('INT') { shutdown }
    Signal.trap('TERM') { shutdown }
  end
  
  def shutdown
    Rails.logger.info "[OrderCreatedConsumer] Closing RabbitMQ connection..."
    RabbitMQClient.close
    exit(0)
  end
end
