# Faraday HTTP client configuration for inter-service communication

module FaradayClient
  class << self
    def connection(base_url:, timeout: 10)
      Faraday.new(url: base_url) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
        
        conn.options.timeout = timeout
        conn.options.open_timeout = 5
        
        conn.headers['Content-Type'] = 'application/json'
        conn.headers['Accept'] = 'application/json'
      end
    end
    
    # Example: Client for User Service
    def user_service
      @user_service ||= connection(
        base_url: ENV.fetch('USER_SERVICE_URL', 'http://localhost:3001')
      )
    end
    
    # Example: Client for Product Service
    def product_service
      @product_service ||= connection(
        base_url: ENV.fetch('PRODUCT_SERVICE_URL', 'http://localhost:3002')
      )
    end
  end
end
