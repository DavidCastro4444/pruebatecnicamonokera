# Customer Service - RabbitMQ Consumer

## Descripción

Consumer de eventos `order.created.v1` desde RabbitMQ que actualiza el contador de órdenes (`orders_count`) de cada cliente con **idempotencia garantizada**.

## Arquitectura

### Componentes

1. **ProcessedEvent** - Tabla para idempotencia
2. **OrderCreatedConsumer** - Consumer principal con manejo de errores
3. **RabbitMQ Initializer** - Configuración de exchanges, queues y DLQ
4. **Rake Tasks** - Comandos para ejecutar y gestionar el consumer

### Flujo de Procesamiento

```
1. Mensaje llega a queue: customer_service.order_created
2. Consumer extrae correlation_id (headers o event_id)
3. Parse del payload JSON
4. Transacción atómica:
   a) Insertar en processed_events (unique constraint)
   b) Si ya existe → SKIP (idempotencia)
   c) Si es nuevo → Incrementar customer.orders_count
5. ACK manual del mensaje
```

### Manejo de Errores

#### Errores Temporales (Requeue)
- `ActiveRecord::ConnectionTimeoutError`
- `ActiveRecord::ConnectionNotEstablished`
- `PG::ConnectionBad`
- `PG::UnableToSend`

**Acción:** NACK con requeue → mensaje vuelve a la cola

#### Errores Permanentes (Dead Letter Queue)
- `ActiveRecord::RecordNotFound` (customer no existe)
- `ActiveRecord::RecordInvalid` (validación falló)
- `JSON::ParserError` (payload inválido)

**Acción:** NACK sin requeue → mensaje va a DLQ

#### Errores Desconocidos
**Acción:** NACK con requeue (por defecto, configurable)

### Dead Letter Queue (DLQ)

Configuración automática:
- **DLX Exchange:** `dlx.order.events`
- **DLQ Queue:** `customer_service.order_created.dlq`
- **Routing Key:** `order.created.failed`

Mensajes que van a DLQ:
- Errores permanentes (RecordNotFound, JSON inválido, etc.)
- Mensajes que exceden reintentos (si configuras TTL/max retries)

## Base de Datos

### Migración: processed_events

```ruby
create_table :processed_events do |t|
  t.string :event_id, null: false
  t.datetime :processed_at, null: false
  t.timestamps
end

add_index :processed_events, :event_id, unique: true
```

**Propósito:** Garantizar que cada evento se procese exactamente una vez (idempotencia).

## Configuración

### Variables de Entorno

Agregar a `.env`:

```bash
# RabbitMQ Connection
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/

# Exchanges
ORDER_EVENTS_EXCHANGE=order.events
DLX_EXCHANGE=dlx.order.events

# Queues
ORDER_CREATED_QUEUE=customer_service.order_created
DLQ_NAME=customer_service.order_created.dlq
```

## Comandos

### 1. Ejecutar Migración

```bash
cd customer_service
rails db:migrate
```

### 2. Setup de Infraestructura RabbitMQ

Crea exchanges, queues y bindings:

```bash
rake rabbitmq:setup
```

**Output esperado:**
```
Setting up RabbitMQ infrastructure...
✓ Order Events Exchange: order.events
✓ Dead Letter Exchange: dlx.order.events
✓ Order Created Queue: customer_service.order_created
✓ Dead Letter Queue: customer_service.order_created.dlq

RabbitMQ infrastructure setup complete!
```

### 3. Iniciar Consumer

```bash
rake rabbitmq:consume
```

**Output esperado:**
```
================================================================================
Starting RabbitMQ Consumer for Customer Service
================================================================================
Queue: customer_service.order_created
Exchange: order.events
Routing Key: order.created
================================================================================

[OrderCreatedConsumer] Starting consumer...
[OrderCreatedConsumer] Listening on queue: customer_service.order_created
```

### 4. Inspeccionar Dead Letter Queue

```bash
rake rabbitmq:inspect_dlq
```

Ver mensajes que fallaron permanentemente.

## Testing en Local

### Escenario 1: Evento Exitoso

**Paso 1:** Iniciar consumer
```bash
# Terminal 1
cd customer_service
rake rabbitmq:consume
```

**Paso 2:** Crear orden desde order_service
```bash
# Terminal 2
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

**Paso 3:** Verificar logs del consumer
```
[OrderCreatedConsumer] [event-uuid] Received message
[OrderCreatedConsumer] [event-uuid] Event ID: event-uuid
[OrderCreatedConsumer] [event-uuid] Updated customer 1: orders_count = 1
[OrderCreatedConsumer] [event-uuid] Message acknowledged
```

**Paso 4:** Verificar en base de datos
```bash
rails console
> Customer.find(1).orders_count
=> 1
> ProcessedEvent.count
=> 1
```

### Escenario 2: Idempotencia (Mensaje Duplicado)

**Paso 1:** Publicar el mismo evento dos veces (simular duplicado)

**Resultado esperado:**
```
[OrderCreatedConsumer] [event-uuid] Event event-uuid already processed, skipping
[OrderCreatedConsumer] [event-uuid] Message acknowledged
```

**Verificación:**
```bash
> Customer.find(1).orders_count
=> 1  # No se incrementó de nuevo
```

### Escenario 3: Customer No Existe (Error Permanente → DLQ)

**Paso 1:** Crear orden con customer_id inexistente
```bash
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "order": {
      "customer_id": 999,
      "product_name": "Test",
      "quantity": 1,
      "price": 10.00
    }
  }'
```

**Logs esperados:**
```
[OrderCreatedConsumer] [event-uuid] Permanent error: ActiveRecord::RecordNotFound
[OrderCreatedConsumer] [event-uuid] Sending to Dead Letter Queue
```

**Verificar DLQ:**
```bash
rake rabbitmq:inspect_dlq
```

### Escenario 4: Error Temporal (Requeue)

Simular desconexión de DB:
```bash
# Detener PostgreSQL temporalmente
sudo service postgresql stop

# El consumer intentará procesar y hará requeue
# Logs:
[OrderCreatedConsumer] [event-uuid] Temporary error: PG::ConnectionBad
[OrderCreatedConsumer] [event-uuid] Requeuing message for retry

# Reiniciar PostgreSQL
sudo service postgresql start

# El mensaje se procesará exitosamente en el siguiente intento
```

## Logs y Correlation ID

El consumer usa **correlation_id** para tracking:

1. **Prioridad 1:** `correlation_id` de headers RabbitMQ
2. **Prioridad 2:** `event_id` del payload
3. **Fallback:** UUID generado

Todos los logs incluyen el correlation_id:
```
[OrderCreatedConsumer] [correlation-id] Mensaje...
```

Esto facilita el debugging y tracing distribuido.

## Monitoreo

### Métricas Importantes

1. **Mensajes procesados:** Count de `processed_events`
2. **Mensajes en DLQ:** `rake rabbitmq:inspect_dlq`
3. **Orders count actualizados:** Verificar `customers.orders_count`

### Queries Útiles

```ruby
# Total eventos procesados
ProcessedEvent.count

# Eventos procesados hoy
ProcessedEvent.where('processed_at > ?', Time.current.beginning_of_day).count

# Clientes con órdenes
Customer.where('orders_count > 0').count

# Último evento procesado
ProcessedEvent.order(processed_at: :desc).first
```

## Producción

### Recomendaciones

1. **Supervisión:** Usar systemd, supervisord o Docker para mantener el consumer corriendo
2. **Múltiples Workers:** Ejecutar varios consumers en paralelo para throughput
3. **Alertas:** Monitorear DLQ y alertar si crece
4. **Retry Policy:** Configurar max retries con TTL en RabbitMQ
5. **Circuit Breaker:** Implementar si hay muchos errores temporales

### Ejemplo systemd

```ini
[Unit]
Description=Customer Service RabbitMQ Consumer
After=network.target postgresql.service rabbitmq-server.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/customer_service
Environment=RAILS_ENV=production
ExecStart=/usr/local/bin/bundle exec rake rabbitmq:consume
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Troubleshooting

### Consumer no recibe mensajes

1. Verificar que RabbitMQ está corriendo: `sudo service rabbitmq-server status`
2. Verificar binding: `rake rabbitmq:setup`
3. Verificar que order_service publica eventos correctamente
4. Revisar logs de RabbitMQ: `/var/log/rabbitmq/`

### Mensajes se acumulan en DLQ

1. Inspeccionar: `rake rabbitmq:inspect_dlq`
2. Identificar patrón de errores en logs
3. Corregir datos o código según el error
4. Opcionalmente, republicar mensajes desde DLQ (requiere script custom)

### Idempotencia no funciona

1. Verificar unique index: `rails db:migrate:status`
2. Verificar que event_id viene en el payload
3. Revisar logs de transacciones

## Resumen

✅ **Idempotencia:** Garantizada con `processed_events` y unique constraint  
✅ **Transaccionalidad:** Todo en una transacción atómica  
✅ **ACK Manual:** Control total sobre confirmación de mensajes  
✅ **Error Handling:** Temporal (requeue) vs Permanente (DLQ)  
✅ **Dead Letter Queue:** Configurado y listo para usar  
✅ **Correlation ID:** Tracking completo en logs  
✅ **Production Ready:** Preparado para supervisión y escalado
