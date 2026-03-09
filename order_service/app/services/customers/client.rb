module Customers
  class Client
    TIMEOUT = 5
    OPEN_TIMEOUT = 2
    
    class ServiceError < StandardError; end
    class NotFoundError < StandardError; end
    class TimeoutError < StandardError; end
    
    def self.fetch(customer_id)
      new.fetch(customer_id)
    end
    
    def fetch(customer_id)
      response = connection.get("/customers/#{customer_id}")
      
      case response.status
      when 200
        normalize_response(response.body)
      when 404
        raise NotFoundError, "Customer #{customer_id} not found"
      when 500..599
        raise ServiceError, "Customer service error: #{response.status}"
      else
        raise ServiceError, "Unexpected response: #{response.status}"
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise TimeoutError, "Customer service timeout or connection failed: #{e.message}"
    end
    
    private
    
    def connection
      @connection ||= Faraday.new(url: base_url) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
        
        conn.options.timeout = TIMEOUT
        conn.options.open_timeout = OPEN_TIMEOUT
        
        conn.headers['Content-Type'] = 'application/json'
        conn.headers['Accept'] = 'application/json'
      end
    end
    
    def base_url
      ENV.fetch('CUSTOMER_SERVICE_URL', 'http://localhost:3001')
    end
    
    def normalize_response(body)
      {
        id: body['id'] || body[:id],
        name: body['name'] || body[:name],
        email: body['email'] || body[:email],
        address: body['address'] || body[:address]
      }
    end
  end
end
