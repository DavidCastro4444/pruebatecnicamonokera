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
    
    # Example: Declare exchange for order events
    def order_events_exchange
      @order_events_exchange ||= channel.topic(
        ENV.fetch('ORDER_EVENTS_EXCHANGE', 'order.events'),
        durable: true
      )
    end
  end
end

# Graceful shutdown
at_exit do
  RabbitMQClient.close
end
