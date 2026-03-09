class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.integer :customer_id, null: false
      t.string :product_name, null: false
      t.integer :quantity, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :status, null: false, default: 'pending'

      t.timestamps
    end
    
    add_index :orders, :customer_id
    add_index :orders, :status
    add_index :orders, :created_at
  end
end
