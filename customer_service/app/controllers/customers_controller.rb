class CustomersController < ApplicationController
  def show
    customer = Customer.find(params[:id])
    
    render json: {
      id: customer.id,
      customer_name: customer.customer_name,
      address: customer.address,
      orders_count: customer.orders_count
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Customer not found' }, status: :not_found
  end
end
