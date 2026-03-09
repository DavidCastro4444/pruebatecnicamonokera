# Customer Service - Setup Instructions

## Initial Setup Commands (From Scratch)

If starting from scratch, use these commands:

```bash
# Create Rails API-only project for customer_service
rails new customer_service --api --database=postgresql --skip-test

# Navigate to project directory
cd customer_service

# Add RSpec
bundle add rspec-rails --group development,test

# Install RSpec
rails generate rspec:install

# Create database
rails db:create

# Run migrations
rails db:migrate

# Seed database with predefined customers
rails db:seed
```

## For Existing Project

```bash
cd customer_service

# Install dependencies
bundle install

# Setup database
rails db:create
rails db:migrate

# Seed database with 5 predefined customers
rails db:seed

# Run server (default port 3001 for customer service)
rails server -p 3001
```

## Environment Variables

Create a `.env` file in the customer_service directory with:

```
# Database
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD=
DB_NAME=customer_service_development

# RabbitMQ (for future consumer implementation)
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
ORDER_EVENTS_EXCHANGE=order.events
```

## Predefined Customers (Seeds)

The database will be seeded with 5 customers:

1. **John Doe** - 123 Main Street, New York, NY 10001, USA
2. **Jane Smith** - 456 Oak Avenue, Los Angeles, CA 90001, USA
3. **Robert Johnson** - 789 Pine Road, Chicago, IL 60601, USA
4. **Maria Garcia** - 321 Elm Boulevard, Miami, FL 33101, USA
5. **David Chen** - 654 Maple Drive, San Francisco, CA 94102, USA

All customers start with `orders_count: 0`

## Test Endpoints

### Health Check
```bash
curl http://localhost:3001/health
```

Expected response:
```json
{
  "status": "ok",
  "service": "customer_service",
  "timestamp": "2026-03-08T18:31:00Z",
  "database": "connected"
}
```

### Get Customer
```bash
curl http://localhost:3001/customers/1
```

Expected response:
```json
{
  "id": 1,
  "customer_name": "John Doe",
  "address": "123 Main Street, New York, NY 10001, USA",
  "orders_count": 0
}
```

### Customer Not Found
```bash
curl http://localhost:3001/customers/999
```

Expected response (404):
```json
{
  "error": "Customer not found"
}
```

## Next Steps

- Implement RabbitMQ consumer to listen for `order.created` events
- Update `orders_count` when orders are created
- Add additional endpoints as needed (index, create, update)
