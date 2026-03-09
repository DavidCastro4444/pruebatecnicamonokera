module Orders
  class Create
    def self.call(params)
      new(params).call
    end
    
    def initialize(params)
      @params = params
      @warnings = []
    end
    
    def call
      order = build_order
      return validation_failure(order) unless order.valid?
      
      order.save!
      customer_data = fetch_customer_data(order.customer_id)
      publish_order_created_event(order)
      
      success_response(order, customer_data)
    rescue StandardError => e
      error_response(e)
    end
    
    private
    
    def build_order
      Order.new(@params)
    end
    
    def validation_failure(order)
      { success: false, errors: order.errors.full_messages }
    end
    
    def success_response(order, customer_data)
      { success: true, data: build_response(order, customer_data) }
    end
    
    def error_response(exception)
      Rails.logger.error("Order creation failed: #{exception.message}")
      { success: false, errors: [exception.message] }
    end
    
    def fetch_customer_data(customer_id)
      Customers::Client.fetch(customer_id)
    rescue StandardError => e
      log_customer_fetch_failure(customer_id, e)
      nil
    end
    
    def log_customer_fetch_failure(customer_id, exception)
      Rails.logger.warn("Failed to fetch customer #{customer_id}: #{exception.message}")
      @warnings << "Customer service unavailable. Customer data not included."
    end
    
    def publish_order_created_event(order)
      Events::PublishOrderCreated.call(order)
    rescue StandardError => e
      Rails.logger.error("Failed to publish order.created event for order #{order.id}: #{e.message}")
    end
    
    def build_response(order, customer_data)
      {
        id: order.id,
        customer_id: order.customer_id,
        product_name: order.product_name,
        quantity: order.quantity,
        price: order.price.to_s,
        status: order.status,
        created_at: order.created_at.iso8601,
        updated_at: order.updated_at.iso8601,
        customer: customer_data
      }.tap { |response| response[:warnings] = @warnings if @warnings.any? }
    end
  end
end
