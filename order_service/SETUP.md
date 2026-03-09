# Order Service - Setup Instructions

## Initial Setup Commands

If starting from scratch, use these commands:

```bash
# Create Rails API-only project for order_service
rails new order_service --api --database=postgresql --skip-test

# Navigate to project directory
cd order_service

# Add RSpec
bundle add rspec-rails --group development,test

# Install RSpec
rails generate rspec:install

# Create database
rails db:create
```

## For Existing Project

```bash
cd order_service

# Install dependencies
bundle install

# Setup database
rails db:create
rails db:migrate

# Run server
rails server -p 3000
```

## Environment Variables

Create a `.env` file in the order_service directory with:

```
# Database
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD=
DB_NAME=order_service_development

# RabbitMQ
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
ORDER_EVENTS_EXCHANGE=order.events

# Other Services
USER_SERVICE_URL=http://localhost:3001
PRODUCT_SERVICE_URL=http://localhost:3002
```

## Test Health Endpoint

```bash
curl http://localhost:3000/health
```

Expected response:
```json
{
  "status": "ok",
  "service": "order_service",
  "timestamp": "2026-03-08T18:14:00Z",
  "database": "connected"
}
```

## Next Steps

- Generate Order model and migrations
- Create order endpoints (CRUD)
- Implement inter-service communication
- Add RabbitMQ event publishing
