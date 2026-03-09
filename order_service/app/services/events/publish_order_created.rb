module Events
  class PublishOrderCreated
    ROUTING_KEY = 'order.created'
    EVENT_TYPE = 'order.created.v1'
    
    def self.call(order)
      new(order).call
    end
    
    def initialize(order)
      @order = order
    end
    
    def call
      publish_event
      log_success
      true
    end
    
    private
    
    def publish_event
      exchange.publish(
        build_payload.to_json,
        routing_key: ROUTING_KEY,
        persistent: true,
        content_type: 'application/json',
        timestamp: Time.current.to_i
      )
    end
    
    def build_payload
      {
        event_id: SecureRandom.uuid,
        occurred_at: Time.current.iso8601,
        type: EVENT_TYPE,
        order: order_attributes
      }
    end
    
    def order_attributes
      {
        id: @order.id,
        customer_id: @order.customer_id,
        product_name: @order.product_name,
        quantity: @order.quantity,
        price: @order.price.to_s,
        status: @order.status
      }
    end
    
    def exchange
      @exchange ||= channel.topic(exchange_name, durable: true)
    end
    
    def channel
      @channel ||= connection.create_channel
    end
    
    def connection
      @connection ||= create_connection
    end
    
    def create_connection
      conn = Bunny.new(connection_config)
      conn.start
      conn
    end
    
    def connection_config
      {
        host: ENV.fetch('RABBITMQ_HOST', 'localhost'),
        port: ENV.fetch('RABBITMQ_PORT', 5672).to_i,
        username: ENV.fetch('RABBITMQ_USERNAME', 'guest'),
        password: ENV.fetch('RABBITMQ_PASSWORD', 'guest'),
        vhost: ENV.fetch('RABBITMQ_VHOST', '/'),
        automatically_recover: true,
        network_recovery_interval: 5,
        connection_timeout: 10
      }
    end
    
    def exchange_name
      ENV.fetch('ORDER_EVENTS_EXCHANGE', 'order.events')
    end
    
    def log_success
      Rails.logger.info("Published order.created event for order #{@order.id}")
    end
  end
end
