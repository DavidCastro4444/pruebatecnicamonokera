class HealthController < ApplicationController
  def show
    render json: {
      status: 'ok',
      service: 'customer_service',
      timestamp: Time.current.iso8601,
      database: database_status
    }, status: :ok
  rescue => e
    render json: {
      status: 'error',
      service: 'customer_service',
      timestamp: Time.current.iso8601,
      error: e.message
    }, status: :service_unavailable
  end
  
  private
  
  def database_status
    ActiveRecord::Base.connection.active? ? 'connected' : 'disconnected'
  end
end
