# RabbitMQ connection configuration using Bunny

module RabbitMQClient
  class << self
    def connection
      @connection ||= Bunny.new(
        host: ENV.fetch('RABBITMQ_HOST', 'localhost'),
        port: ENV.fetch('RABBITMQ_PORT', 5672).to_i,
        username: ENV.fetch('RABBITMQ_USERNAME', 'guest'),
        password: ENV.fetch('RABBITMQ_PASSWORD', 'guest'),
        vhost: ENV.fetch('RABBITMQ_VHOST', '/'),
        automatically_recover: true,
        network_recovery_interval: 5,
        connection_timeout: 10
      )
    end
    
    def start
      connection.start unless connection.open?
      connection
    end
    
    def channel
      @channel ||= start.create_channel
    end
    
    def close
      @channel&.close
      @connection&.close
      @channel = nil
      @connection = nil
    end
    
    # Exchange for order events
    def order_events_exchange
      @order_events_exchange ||= channel.topic(
        ENV.fetch('ORDER_EVENTS_EXCHANGE', 'order.events'),
        durable: true
      )
    end
    
    # Queue for consuming order.created events
    def order_created_queue
      @order_created_queue ||= begin
        queue = channel.queue(
          ENV.fetch('ORDER_CREATED_QUEUE', 'customer_service.order_created'),
          durable: true,
          arguments: {
            # Dead Letter Exchange configuration
            'x-dead-letter-exchange' => ENV.fetch('DLX_EXCHANGE', 'dlx.order.events'),
            'x-dead-letter-routing-key' => 'order.created.failed'
          }
        )
        
        # Bind queue to exchange with routing key
        queue.bind(order_events_exchange, routing_key: 'order.created')
        
        queue
      end
    end
    
    # Dead Letter Exchange (for failed messages)
    def dead_letter_exchange
      @dead_letter_exchange ||= channel.topic(
        ENV.fetch('DLX_EXCHANGE', 'dlx.order.events'),
        durable: true
      )
    end
    
    # Dead Letter Queue (stores permanently failed messages)
    def dead_letter_queue
      @dead_letter_queue ||= begin
        queue = channel.queue(
          ENV.fetch('DLQ_NAME', 'customer_service.order_created.dlq'),
          durable: true
        )
        
        queue.bind(dead_letter_exchange, routing_key: 'order.created.failed')
        
        queue
      end
    end
  end
end

# Graceful shutdown
at_exit do
  RabbitMQClient.close
end
