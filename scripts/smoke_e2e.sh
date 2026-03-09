#!/bin/bash

# Smoke Test End-to-End
# Tests the complete flow: Order Service -> RabbitMQ -> Customer Service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MAX_RETRIES=30
RETRY_INTERVAL=2
ORDER_SERVICE_URL="http://localhost:3001"
CUSTOMER_SERVICE_URL="http://localhost:3002"
CUSTOMER_ID=1

echo "=========================================="
echo "  E2E Smoke Test - Microservices"
echo "=========================================="
echo ""

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Function to check if service is healthy
check_service_health() {
    local service_name=$1
    local health_url=$2
    local max_wait=$3
    
    print_info "Waiting for $service_name to be healthy..."
    
    for i in $(seq 1 $max_wait); do
        if curl -s -f "$health_url" > /dev/null 2>&1; then
            print_success "$service_name is healthy"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    
    echo ""
    print_error "$service_name failed to become healthy"
    return 1
}

# Function to get customer orders_count
get_orders_count() {
    local customer_id=$1
    local response=$(curl -s "$CUSTOMER_SERVICE_URL/customers/$customer_id")
    
    if [ $? -ne 0 ]; then
        echo "0"
        return 1
    fi
    
    echo "$response" | grep -o '"orders_count":[0-9]*' | grep -o '[0-9]*'
}

# Step 1: Start docker-compose
print_info "Step 1: Starting docker-compose..."
docker-compose down -v > /dev/null 2>&1 || true
docker-compose up -d

if [ $? -ne 0 ]; then
    print_error "Failed to start docker-compose"
    exit 1
fi

print_success "Docker-compose started"
echo ""

# Step 2: Wait for services to be healthy
print_info "Step 2: Waiting for services to be ready..."

check_service_health "Order Service" "$ORDER_SERVICE_URL/health" 30
if [ $? -ne 0 ]; then
    print_error "Order Service health check failed"
    docker-compose logs order_service
    exit 1
fi

check_service_health "Customer Service" "$CUSTOMER_SERVICE_URL/health" 30
if [ $? -ne 0 ]; then
    print_error "Customer Service health check failed"
    docker-compose logs customer_service
    exit 1
fi

echo ""

# Step 3: Setup databases
print_info "Step 3: Setting up databases..."

print_info "Creating Order Service database..."
docker-compose exec -T order_service rails db:create > /dev/null 2>&1 || true
docker-compose exec -T order_service rails db:migrate > /dev/null 2>&1

print_info "Creating Customer Service database..."
docker-compose exec -T customer_service rails db:create > /dev/null 2>&1 || true
docker-compose exec -T customer_service rails db:migrate > /dev/null 2>&1
docker-compose exec -T customer_service rails db:seed > /dev/null 2>&1

print_success "Databases ready"
echo ""

# Step 4: Setup RabbitMQ infrastructure
print_info "Step 4: Setting up RabbitMQ..."
docker-compose exec -T customer_service rake rabbitmq:setup > /dev/null 2>&1

print_success "RabbitMQ infrastructure ready"
echo ""

# Step 5: Start RabbitMQ consumer
print_info "Step 5: Starting RabbitMQ consumer..."
docker-compose exec -d customer_service rake rabbitmq:consume

sleep 3
print_success "Consumer started"
echo ""

# Step 6: Get initial orders_count
print_info "Step 6: Getting initial customer state..."

INITIAL_COUNT=$(get_orders_count $CUSTOMER_ID)
if [ $? -ne 0 ]; then
    print_error "Failed to get initial orders_count"
    exit 1
fi

print_info "Customer $CUSTOMER_ID initial orders_count: $INITIAL_COUNT"
echo ""

# Step 7: Create an order
print_info "Step 7: Creating order via Order Service..."

ORDER_PAYLOAD='{
  "order": {
    "customer_id": '$CUSTOMER_ID',
    "product_name": "E2E Test Laptop",
    "quantity": 1,
    "price": 999.99
  }
}'

ORDER_RESPONSE=$(curl -s -X POST "$ORDER_SERVICE_URL/orders" \
  -H "Content-Type: application/json" \
  -d "$ORDER_PAYLOAD")

if [ $? -ne 0 ]; then
    print_error "Failed to create order"
    exit 1
fi

# Check if order was created (status 201)
ORDER_ID=$(echo "$ORDER_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')

if [ -z "$ORDER_ID" ]; then
    print_error "Order creation failed - no order ID returned"
    echo "Response: $ORDER_RESPONSE"
    exit 1
fi

print_success "Order created with ID: $ORDER_ID"
echo ""

# Step 8: Wait for event processing (with retries)
print_info "Step 8: Waiting for event processing..."
print_info "Checking if orders_count increments (max ${MAX_RETRIES} retries, ${RETRY_INTERVAL}s interval)..."

EXPECTED_COUNT=$((INITIAL_COUNT + 1))
CURRENT_COUNT=$INITIAL_COUNT

for i in $(seq 1 $MAX_RETRIES); do
    CURRENT_COUNT=$(get_orders_count $CUSTOMER_ID)
    
    if [ "$CURRENT_COUNT" -eq "$EXPECTED_COUNT" ]; then
        print_success "Event processed! orders_count incremented from $INITIAL_COUNT to $CURRENT_COUNT"
        echo ""
        print_success "=========================================="
        print_success "  E2E SMOKE TEST PASSED ✓"
        print_success "=========================================="
        echo ""
        echo "Summary:"
        echo "  - Order created: ID $ORDER_ID"
        echo "  - Customer ID: $CUSTOMER_ID"
        echo "  - Initial orders_count: $INITIAL_COUNT"
        echo "  - Final orders_count: $CURRENT_COUNT"
        echo "  - Event processing time: ~$((i * RETRY_INTERVAL)) seconds"
        echo ""
        exit 0
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        print_info "Still waiting... (attempt $i/$MAX_RETRIES, current count: $CURRENT_COUNT)"
    else
        echo -n "."
    fi
    
    sleep $RETRY_INTERVAL
done

echo ""
print_error "Event processing timeout!"
print_error "Expected orders_count: $EXPECTED_COUNT"
print_error "Current orders_count: $CURRENT_COUNT"
echo ""

print_info "Debugging information:"
echo ""

print_info "Order Service logs (last 20 lines):"
docker-compose logs --tail=20 order_service

echo ""
print_info "Customer Service logs (last 20 lines):"
docker-compose logs --tail=20 customer_service

echo ""
print_info "RabbitMQ Management UI: http://localhost:15672 (guest/guest)"

exit 1
