# Order Service - API Examples

## Endpoints

### POST /orders - Create Order

Creates a new order, fetches customer data from Customer Service, and publishes an event to RabbitMQ.

**Request:**
```bash
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "order": {
      "customer_id": 1,
      "product_name": "Laptop Dell XPS 15",
      "quantity": 2,
      "price": 1299.99
    }
  }'
```

**Success Response (200 OK):**
```json
{
  "id": 1,
  "customer_id": 1,
  "product_name": "Laptop Dell XPS 15",
  "quantity": 2,
  "price": "1299.99",
  "status": "pending",
  "created_at": "2026-03-08T18:19:00Z",
  "updated_at": "2026-03-08T18:19:00Z",
  "customer": {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "address": "123 Main St, City, Country"
  }
}
```

**Success Response with Customer Service Down (201 Created with Warning):**
```json
{
  "id": 1,
  "customer_id": 1,
  "product_name": "Laptop Dell XPS 15",
  "quantity": 2,
  "price": "1299.99",
  "status": "pending",
  "created_at": "2026-03-08T18:19:00Z",
  "updated_at": "2026-03-08T18:19:00Z",
  "customer": null,
  "warnings": [
    "Customer service unavailable. Customer data not included."
  ]
}
```

**Validation Error Response (422 Unprocessable Entity):**
```json
{
  "errors": [
    "Customer can't be blank",
    "Quantity must be greater than 0"
  ]
}
```

---

### GET /orders - List Orders by Customer

Retrieves all orders for a specific customer. The `customer_id` parameter is **required**.

**Request:**
```bash
curl -X GET "http://localhost:3000/orders?customer_id=1" \
  -H "Content-Type: application/json"
```

**Success Response (200 OK):**
```json
[
  {
    "id": 3,
    "customer_id": 1,
    "product_name": "Wireless Mouse",
    "quantity": 1,
    "price": "29.99",
    "status": "pending",
    "created_at": "2026-03-08T18:25:00Z",
    "updated_at": "2026-03-08T18:25:00Z"
  },
  {
    "id": 2,
    "customer_id": 1,
    "product_name": "USB-C Cable",
    "quantity": 3,
    "price": "15.99",
    "status": "confirmed",
    "created_at": "2026-03-08T18:20:00Z",
    "updated_at": "2026-03-08T18:20:00Z"
  },
  {
    "id": 1,
    "customer_id": 1,
    "product_name": "Laptop Dell XPS 15",
    "quantity": 2,
    "price": "1299.99",
    "status": "pending",
    "created_at": "2026-03-08T18:19:00Z",
    "updated_at": "2026-03-08T18:19:00Z"
  }
]
```

**Missing customer_id Parameter (400 Bad Request):**
```bash
curl -X GET "http://localhost:3000/orders" \
  -H "Content-Type: application/json"
```

Response:
```json
{
  "error": "customer_id parameter is required"
}
```

---

## RabbitMQ Event Published

When an order is successfully created, the following event is published to RabbitMQ:

**Exchange:** `order.events` (topic)  
**Routing Key:** `order.created`  
**Payload:**

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "occurred_at": "2026-03-08T18:19:00Z",
  "type": "order.created.v1",
  "order": {
    "id": 1,
    "customer_id": 1,
    "product_name": "Laptop Dell XPS 15",
    "quantity": 2,
    "price": "1299.99",
    "status": "pending"
  }
}
```

---

## Error Handling Strategy

### Customer Service Failures

**Design Decision:** If the Customer Service is unavailable or returns an error, the order is **still created successfully** (201 Created).

**Rationale:**
- **Resilience:** We don't want another service's failure to block order creation
- **Availability:** Business operations can continue even if Customer Service is down
- **Eventual Consistency:** Customer data can be fetched later via retry/polling mechanisms
- **Transparency:** The `warnings` field informs the client about the partial failure

**Response:** 201 Created with `customer: null` and a warning message.

### RabbitMQ Failures

**Design Decision:** If RabbitMQ publishing fails, the order is **still created successfully** (201 Created).

**Rationale:**
- **Core Operation Priority:** Order creation is the primary operation and must succeed
- **Async Nature:** Events are for asynchronous notification, not critical for the transaction
- **Retry Mechanisms:** Can implement background jobs to republish failed events
- **Infrastructure Independence:** Infrastructure issues shouldn't block business operations

**Response:** 201 Created (normal response), error is logged server-side only.

---

## Testing Scenarios

### 1. Happy Path - All Services Available
```bash
# Ensure Customer Service is running on port 3001
# Ensure RabbitMQ is running

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
```

Expected: 201 Created with full customer data

### 2. Customer Service Down
```bash
# Stop Customer Service or use invalid customer_id

curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "order": {
      "customer_id": 999,
      "product_name": "Test Product",
      "quantity": 1,
      "price": 99.99
    }
  }'
```

Expected: 201 Created with `customer: null` and warning

### 3. Invalid Order Data
```bash
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "order": {
      "customer_id": 1,
      "product_name": "",
      "quantity": -1,
      "price": 99.99
    }
  }'
```

Expected: 422 Unprocessable Entity with validation errors

### 4. List Orders
```bash
# Create a few orders first, then:

curl -X GET "http://localhost:3000/orders?customer_id=1"
```

Expected: 200 OK with array of orders (newest first)
