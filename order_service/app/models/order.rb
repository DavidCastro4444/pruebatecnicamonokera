class Order < ApplicationRecord
  validates :customer_id, presence: true
  validates :product_name, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: %w[pending confirmed shipped delivered cancelled] }
  
  before_validation :set_default_status, on: :create
  
  private
  
  def set_default_status
    self.status ||= 'pending'
  end
end
