# End-to-End Smoke Test

## Descripción

Script de smoke test que valida el flujo completo de microservicios:

1. **Order Service** recibe POST /orders
2. **RabbitMQ** transmite evento `order.created.v1`
3. **Customer Service** consume evento e incrementa `orders_count`

## Requisitos Previos

- Docker y Docker Compose instalados
- Puertos disponibles: 3001, 3002, 5672, 15672, 5433, 5434
- Bash shell (Linux, macOS, WSL en Windows)

## Ejecución Rápida

```bash
# Desde la raíz del monorepo
chmod +x scripts/smoke_e2e.sh
./scripts/smoke_e2e.sh
```

## Qué Hace el Script

### 1. Levanta Docker Compose

```bash
docker-compose down -v  # Limpia estado anterior
docker-compose up -d    # Inicia todos los servicios
```

### 2. Verifica Health de Servicios

Espera hasta 30 segundos por servicio:
- Order Service: `http://localhost:3001/health`
- Customer Service: `http://localhost:3002/health`

### 3. Setup de Bases de Datos

```bash
# Order Service
docker-compose exec order_service rails db:create db:migrate

# Customer Service (incluye seeds con 5 clientes)
docker-compose exec customer_service rails db:create db:migrate db:seed
```

### 4. Setup de RabbitMQ

```bash
docker-compose exec customer_service rake rabbitmq:setup
```

Crea:
- Exchange: `order.events`
- Queue: `customer_service.order_created`
- Dead Letter Queue: `customer_service.order_created.dlq`

### 5. Inicia Consumer

```bash
docker-compose exec -d customer_service rake rabbitmq:consume
```

### 6. Obtiene Estado Inicial

```bash
GET http://localhost:3002/customers/1
# Guarda orders_count inicial
```

### 7. Crea Orden

```bash
POST http://localhost:3001/orders
{
  "order": {
    "customer_id": 1,
    "product_name": "E2E Test Laptop",
    "quantity": 1,
    "price": 999.99
  }
}
```

### 8. Verifica Incremento (con Retries)

Polling con backoff:
- **Max retries:** 30
- **Intervalo:** 2 segundos
- **Timeout total:** ~60 segundos

Verifica que `orders_count` se incrementó de N a N+1.

## Output Exitoso

```
==========================================
  E2E Smoke Test - Microservices
==========================================

ℹ Step 1: Starting docker-compose...
✓ Docker-compose started

ℹ Step 2: Waiting for services to be ready...
ℹ Waiting for Order Service to be healthy...
✓ Order Service is healthy
ℹ Waiting for Customer Service to be healthy...
✓ Customer Service is healthy

ℹ Step 3: Setting up databases...
✓ Databases ready

ℹ Step 4: Setting up RabbitMQ...
✓ RabbitMQ infrastructure ready

ℹ Step 5: Starting RabbitMQ consumer...
✓ Consumer started

ℹ Step 6: Getting initial customer state...
ℹ Customer 1 initial orders_count: 0

ℹ Step 7: Creating order via Order Service...
✓ Order created with ID: 1

ℹ Step 8: Waiting for event processing...
ℹ Checking if orders_count increments (max 30 retries, 2s interval)...
✓ Event processed! orders_count incremented from 0 to 1

✓ ==========================================
✓   E2E SMOKE TEST PASSED ✓
✓ ==========================================

Summary:
  - Order created: ID 1
  - Customer ID: 1
  - Initial orders_count: 0
  - Final orders_count: 1
  - Event processing time: ~4 seconds
```

## Output en Caso de Fallo

Si el test falla, el script muestra:

1. **Error específico** (timeout, health check, etc.)
2. **Logs de Order Service** (últimas 20 líneas)
3. **Logs de Customer Service** (últimas 20 líneas)
4. **Link a RabbitMQ Management UI** para debugging

Ejemplo:

```
✗ Event processing timeout!
✗ Expected orders_count: 1
✗ Current orders_count: 0

ℹ Debugging information:

ℹ Order Service logs (last 20 lines):
[logs...]

ℹ Customer Service logs (last 20 lines):
[logs...]

ℹ RabbitMQ Management UI: http://localhost:15672 (guest/guest)
```

## Debugging

### Ver Logs en Tiempo Real

```bash
# Todos los servicios
docker-compose logs -f

# Servicio específico
docker-compose logs -f order_service
docker-compose logs -f customer_service
docker-compose logs -f rabbitmq
```

### Verificar Estado de RabbitMQ

1. Abrir http://localhost:15672
2. Login: `guest` / `guest`
3. Ir a "Queues" tab
4. Verificar:
   - `customer_service.order_created` - debe tener 0 mensajes (procesados)
   - `customer_service.order_created.dlq` - debe estar vacío (sin errores)

### Verificar Bases de Datos

```bash
# Order Service
docker-compose exec order_service rails console
> Order.count
> Order.last

# Customer Service
docker-compose exec customer_service rails console
> Customer.find(1).orders_count
> ProcessedEvent.count
```

### Re-ejecutar Consumer Manualmente

```bash
# Detener consumer actual
docker-compose exec customer_service pkill -f rabbitmq:consume

# Iniciar en foreground (ver logs)
docker-compose exec customer_service rake rabbitmq:consume
```

## Troubleshooting

### Error: "Port already in use"

```bash
# Ver qué está usando los puertos
lsof -i :3001
lsof -i :3002
lsof -i :5672

# Detener servicios conflictivos
docker-compose down
```

### Error: "Service unhealthy"

```bash
# Ver logs del servicio
docker-compose logs order_service
docker-compose logs customer_service

# Verificar que PostgreSQL esté corriendo
docker-compose ps postgres_order
docker-compose ps postgres_customer
```

### Error: "Event processing timeout"

Posibles causas:

1. **Consumer no está corriendo:**
   ```bash
   docker-compose exec customer_service ps aux | grep rabbitmq
   ```

2. **RabbitMQ no configurado:**
   ```bash
   docker-compose exec customer_service rake rabbitmq:setup
   ```

3. **Evento no se publicó:**
   - Verificar logs de Order Service
   - Verificar RabbitMQ Management UI

4. **Customer no existe:**
   ```bash
   docker-compose exec customer_service rails console
   > Customer.find(1)
   ```

### Reset Completo

```bash
# Detener todo y eliminar volúmenes
docker-compose down -v

# Re-ejecutar smoke test
./scripts/smoke_e2e.sh
```

## Configuración Avanzada

### Cambiar Timeouts

Editar `scripts/smoke_e2e.sh`:

```bash
# Línea 12-13
MAX_RETRIES=30        # Número de intentos
RETRY_INTERVAL=2      # Segundos entre intentos
```

### Cambiar Customer ID

```bash
# Línea 15
CUSTOMER_ID=1         # ID del customer a testear
```

### Ejecutar Sin Limpiar Estado

Comentar línea 76:

```bash
# docker-compose down -v > /dev/null 2>&1 || true
```

## Integración Continua

### GitHub Actions

```yaml
name: E2E Smoke Test

on: [push, pull_request]

jobs:
  smoke-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Run smoke test
        run: |
          chmod +x scripts/smoke_e2e.sh
          ./scripts/smoke_e2e.sh
      
      - name: Cleanup
        if: always()
        run: docker-compose down -v
```

### GitLab CI

```yaml
smoke-test:
  stage: test
  script:
    - chmod +x scripts/smoke_e2e.sh
    - ./scripts/smoke_e2e.sh
  after_script:
    - docker-compose down -v
```

## Métricas del Test

El script reporta:
- **Tiempo de procesamiento de evento:** Cuánto tardó el consumer
- **IDs de recursos:** Order ID, Customer ID
- **Contadores:** Initial vs Final orders_count

Ejemplo:

```
Summary:
  - Order created: ID 1
  - Customer ID: 1
  - Initial orders_count: 0
  - Final orders_count: 1
  - Event processing time: ~4 seconds
```

## Notas

- El script es **idempotente**: puede ejecutarse múltiples veces
- Usa `docker-compose down -v` para limpiar estado entre ejecuciones
- Los seeds crean 5 customers (IDs 1-5) con orders_count=0
- El consumer procesa eventos en ~2-5 segundos típicamente
- Timeout de 60 segundos es suficiente para entornos locales

## Próximos Pasos

Después de un smoke test exitoso:

1. Ejecutar tests unitarios: `bundle exec rspec`
2. Verificar cobertura de código
3. Ejecutar tests de carga (opcional)
4. Deploy a staging/producción
