# Order Service - Implementation Summary

## Files Created/Modified

### 1. Model
- **`app/models/order.rb`** - Order model with validations

### 2. Migration
- **`db/migrate/20260308181906_create_orders.rb`** - Creates orders table with constraints and indexes

### 3. Routes
- **`config/routes.rb`** - Added `resources :orders, only: [:create, :index]`

### 4. Controller
- **`app/controllers/orders_controller.rb`** - Handles POST /orders and GET /orders

### 5. Service Objects
- **`app/services/orders/create.rb`** - Orchestrates order creation, customer fetch, and event publishing
- **`app/services/customers/client.rb`** - Faraday HTTP client for Customer Service with timeout and error handling
- **`app/services/events/publish_order_created.rb`** - RabbitMQ event publisher using Bunny

### 6. Documentation
- **`API_EXAMPLES.md`** - Complete API documentation with curl examples
- **`IMPLEMENTATION_SUMMARY.md`** - This file

## Database Schema

```ruby
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
```

## API Endpoints

### POST /orders
- Validates order data
- Persists order to database
- Fetches customer data from Customer Service (HTTP)
- Publishes `order.created.v1` event to RabbitMQ
- Returns enriched JSON with customer data

### GET /orders?customer_id=X
- Lists all orders for a specific customer
- `customer_id` parameter is **required**
- Orders sorted by created_at DESC

## Error Handling Strategy

### Customer Service Failures
**Decision:** Return 201 Created with `customer: null` and warning

**Rationale:**
- Order creation is the core operation and must succeed
- Resilience: don't let external service failures block our service
- Eventual consistency: customer data can be fetched later
- Transparency: warning informs client of partial failure

### RabbitMQ Failures
**Decision:** Return 201 Created, log error server-side

**Rationale:**
- Events are for async notification, not critical for transaction
- Order persistence is more important than event publishing
- Can implement retry/republishing mechanisms later
- Infrastructure issues shouldn't block business operations

## Event Payload

```json
{
  "event_id": "uuid-v4",
  "occurred_at": "ISO8601 timestamp",
  "type": "order.created.v1",
  "order": {
    "id": 1,
    "customer_id": 1,
    "product_name": "Product Name",
    "quantity": 2,
    "price": "99.99",
    "status": "pending"
  }
}
```

Published to:
- **Exchange:** `order.events` (topic, durable)
- **Routing Key:** `order.created`

## Environment Variables Required

```bash
# Customer Service
CUSTOMER_SERVICE_URL=http://localhost:3001

# RabbitMQ
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
ORDER_EVENTS_EXCHANGE=order.events
```

## Setup Commands

```bash
cd order_service

# Install dependencies
bundle install

# Run migration
rails db:migrate

# Start server
rails server -p 3000
```

## Testing

See `API_EXAMPLES.md` for detailed curl examples and testing scenarios.

### Quick Test
```bash
# Create order
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "order": {
      "customer_id": 1,
      "product_name": "Test Product",
      "quantity": 1,
      "price": 99.99
    }
  }'

# List orders
curl -X GET "http://localhost:3000/orders?customer_id=1"
```

## Architecture Highlights

1. **Service Objects Pattern:** Business logic separated from controllers
2. **Resilient Design:** Graceful degradation when dependencies fail
3. **Event-Driven:** Publishes events for async processing by other services
4. **HTTP Client:** Faraday with timeout and error handling
5. **Message Queue:** Bunny (RabbitMQ) for reliable event publishing
6. **Clean Separation:** Controllers → Services → External APIs/Events
