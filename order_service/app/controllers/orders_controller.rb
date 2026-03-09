class OrdersController < ApplicationController
  before_action :validate_customer_id_param, only: [:index]
  
  def create
    result = Orders::Create.call(order_params)
    
    if result[:success]
      render json: result[:data], status: :created
    else
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    end
  end
  
  def index
    orders = Order.where(customer_id: params[:customer_id]).order(created_at: :desc)
    
    render json: orders, status: :ok
  end
  
  private
  
  def order_params
    params.require(:order).permit(:customer_id, :product_name, :quantity, :price)
  end
  
  def validate_customer_id_param
    unless params[:customer_id].present?
      render json: { error: 'customer_id parameter is required' }, status: :bad_request
    end
  end
end
