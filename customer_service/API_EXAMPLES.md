# Customer Service - API Examples

## Endpoints

### GET /customers/:id - Get Customer by ID

Retrieves a customer's information including their order count.

**Request:**
```bash
curl -X GET http://localhost:3001/customers/1 \
  -H "Content-Type: application/json"
```

**Success Response (200 OK):**
```json
{
  "id": 1,
  "customer_name": "John Doe",
  "address": "123 Main Street, New York, NY 10001, USA",
  "orders_count": 0
}
```

**Not Found Response (404 Not Found):**
```bash
curl -X GET http://localhost:3001/customers/999 \
  -H "Content-Type: application/json"
```

Response:
```json
{
  "error": "Customer not found"
}
```

---

### GET /health - Health Check

Returns the service health status and database connectivity.

**Request:**
```bash
curl -X GET http://localhost:3001/health \
  -H "Content-Type: application/json"
```

**Success Response (200 OK):**
```json
{
  "status": "ok",
  "service": "customer_service",
  "timestamp": "2026-03-08T18:31:38Z",
  "database": "connected"
}
```

**Error Response (503 Service Unavailable):**
```json
{
  "status": "error",
  "service": "customer_service",
  "timestamp": "2026-03-08T18:31:38Z",
  "error": "database connection failed"
}
```

---

## Testing Scenarios

### 1. Get All Seeded Customers

```bash
# Customer 1 - John Doe
curl http://localhost:3001/customers/1

# Customer 2 - Jane Smith
curl http://localhost:3001/customers/2

# Customer 3 - Robert Johnson
curl http://localhost:3001/customers/3

# Customer 4 - Maria Garcia
curl http://localhost:3001/customers/4

# Customer 5 - David Chen
curl http://localhost:3001/customers/5
```

### 2. Test Error Handling

```bash
# Non-existent customer
curl http://localhost:3001/customers/999

# Invalid ID format
curl http://localhost:3001/customers/abc
```

### 3. Integration with Order Service

When the Order Service creates an order for customer ID 1:

```bash
# From order_service (port 3000)
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "order": {
      "customer_id": 1,
      "product_name": "Laptop",
      "quantity": 1,
      "price": 999.99
    }
  }'
```

The Order Service will call:
```bash
# Internal call from order_service to customer_service
GET http://localhost:3001/customers/1
```

And receive customer data to enrich the order response.

---

## Database Schema

```ruby
create_table :customers do |t|
  t.string :customer_name, null: false
  t.string :address, null: false
  t.integer :orders_count, null: false, default: 0
  t.timestamps
end

add_index :customers, :customer_name
```

## Design Decisions

### Why use `id` instead of `external_id`?

**Decision:** Use Rails default auto-incremental `id` as the primary identifier.

**Justification:**
1. **Simplicity** - Rails handles auto-incremental IDs automatically
2. **Consistency** - All Rails models use `id` by default
3. **Performance** - Primary key indexes on `id` are highly optimized
4. **Interoperability** - Other services can reference `customer_id` directly
5. **No current need for external_id** because:
   - No legacy system integration required
   - Internal API between trusted services
   - No ID collision risk in simple distributed setup
   - No security requirement to hide internal IDs

If future requirements demand integration with external systems, we can add `external_id` as an additional column without breaking the existing API.

---

## Future Enhancements

1. **Additional Endpoints** - GET /customers (list), POST /customers (create)
2. **Pagination** - For customer listing
3. **Search** - Search customers by name or address
4. **Caching** - Redis cache for frequently accessed customers
