namespace :rabbitmq do
  desc "Start RabbitMQ consumer for order.created events"
  task consume: :environment do
    puts "=" * 80
    puts "Starting RabbitMQ Consumer for Customer Service"
    puts "=" * 80
    puts "Queue: #{ENV.fetch('ORDER_CREATED_QUEUE', 'customer_service.order_created')}"
    puts "Exchange: #{ENV.fetch('ORDER_EVENTS_EXCHANGE', 'order.events')}"
    puts "Routing Key: order.created"
    puts "=" * 80
    puts ""
    
    OrderCreatedConsumer.start
  end
  
  desc "Setup RabbitMQ infrastructure (exchanges, queues, bindings)"
  task setup: :environment do
    puts "Setting up RabbitMQ infrastructure..."
    
    # Ensure exchanges and queues are created
    RabbitMQClient.order_events_exchange
    RabbitMQClient.dead_letter_exchange
    RabbitMQClient.order_created_queue
    RabbitMQClient.dead_letter_queue
    
    puts "✓ Order Events Exchange: #{ENV.fetch('ORDER_EVENTS_EXCHANGE', 'order.events')}"
    puts "✓ Dead Letter Exchange: #{ENV.fetch('DLX_EXCHANGE', 'dlx.order.events')}"
    puts "✓ Order Created Queue: #{ENV.fetch('ORDER_CREATED_QUEUE', 'customer_service.order_created')}"
    puts "✓ Dead Letter Queue: #{ENV.fetch('DLQ_NAME', 'customer_service.order_created.dlq')}"
    puts ""
    puts "RabbitMQ infrastructure setup complete!"
    
    RabbitMQClient.close
  end
  
  desc "Inspect Dead Letter Queue"
  task inspect_dlq: :environment do
    queue = RabbitMQClient.dead_letter_queue
    message_count = queue.message_count
    
    puts "=" * 80
    puts "Dead Letter Queue Inspection"
    puts "=" * 80
    puts "Queue Name: #{queue.name}"
    puts "Messages: #{message_count}"
    puts "=" * 80
    
    if message_count > 0
      puts "\nFetching messages (non-destructive peek)..."
      
      queue.subscribe(manual_ack: true, block: false) do |delivery_info, properties, payload|
        puts "\n--- Message ---"
        puts "Delivery Tag: #{delivery_info.delivery_tag}"
        puts "Routing Key: #{delivery_info.routing_key}"
        puts "Payload: #{payload}"
        puts "Properties: #{properties.inspect}"
        
        # NACK with requeue to keep message in DLQ
        RabbitMQClient.channel.nack(delivery_info.delivery_tag, false, true)
        
        break # Only show first message
      end
    else
      puts "\nNo messages in Dead Letter Queue"
    end
    
    RabbitMQClient.close
  end
end
