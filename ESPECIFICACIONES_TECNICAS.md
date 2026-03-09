# Especificaciones Técnicas - Sistema de Microservicios Rails


---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Arquitectura del Sistema](#2-arquitectura-del-sistema)
3. [Especificación 1: Comunicación HTTP entre Microservicios](#3-especificación-1-comunicación-http-entre-microservicios)
4. [Especificación 2: Arquitectura Orientada a Eventos](#4-especificación-2-arquitectura-orientada-a-eventos)
5. [Especificación 3: Suite de Pruebas](#5-especificación-3-suite-de-pruebas)
6. [Especificación 4: Documentación del Sistema](#6-especificación-4-documentación-del-sistema)
7. [Requisitos No Funcionales](#7-requisitos-no-funcionales)
8. [Decisiones de Diseño](#8-decisiones-de-diseño)
9. [Apéndices](#9-apéndices)

---

## 1. Resumen Ejecutivo

### 1.1 Propósito del Documento

Este documento describe las especificaciones técnicas del sistema de microservicios implementado con Ruby on Rails, detallando la arquitectura, patrones de comunicación, estrategias de testing y documentación del proyecto.

### 1.2 Alcance

El sistema consta de dos microservicios independientes:

- **Order Service**: Gestión de órdenes de compra
- **Customer Service**: Gestión de información de clientes

Ambos servicios se comunican mediante:
- **Comunicación Síncrona**: HTTP/REST (Faraday)
- **Comunicación Asíncrona**: Mensajería basada en eventos (RabbitMQ)

### 1.3 Stack Tecnológico

| Componente | Tecnología | Versión |
|------------|------------|---------|
| Framework Backend | Ruby on Rails (API-only) | 7.x |
| Lenguaje | Ruby | 3.x |
| HTTP Client | Faraday | 2.x |
| Message Broker | RabbitMQ | 3.x |
| AMQP Client | Bunny | 2.x |
| Base de Datos | PostgreSQL | 15.x |
| Testing Framework | RSpec | 3.x |
| Containerización | Docker / Docker Compose | Latest |

---

## 2. Arquitectura del Sistema

### 2.1 Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENTE API                             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   Order Service      │
              │   (Puerto 3001)      │
              │                      │
              │  ┌────────────────┐  │
              │  │ Orders::Create │  │
              │  └────────┬───────┘  │
              └───────────┼──────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
   │  HTTP GET   │ │  Persist    │ │  Publish    │
   │  Customer   │ │  Order      │ │  Event      │
   │  Data       │ │  to DB      │ │  RabbitMQ   │
   └──────┬──────┘ └─────────────┘ └──────┬──────┘
          │                               │
          ▼                               ▼
   ┌─────────────┐              ┌──────────────────┐
   │  Customer   │              │    RabbitMQ      │
   │  Service    │              │                  │
   │ (Puerto     │              │  Exchange:       │
   │  3002)      │              │  order.events    │
   │             │              │                  │
   │ GET         │              │  Queue:          │
   │ /customers  │              │  customer_       │
   │ /:id        │              │  service.order_  │
   └─────────────┘              │  created         │
                                └────────┬─────────┘
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │  Customer Service    │
                              │                      │
                              │  OrderCreated        │
                              │  Consumer            │
                              │                      │
                              │  ┌────────────────┐  │
                              │  │ Idempotency    │  │
                              │  │ Check          │  │
                              │  └────────┬───────┘  │
                              │           │          │
                              │           ▼          │
                              │  ┌────────────────┐  │
                              │  │ Increment      │  │
                              │  │ orders_count   │  │
                              │  └────────────────┘  │
                              └──────────────────────┘
```

### 2.2 Patrón de Base de Datos

**Database per Service Pattern**: Cada microservicio posee su propia base de datos PostgreSQL independiente, garantizando:

- **Autonomía**: Servicios completamente desacoplados
- **Escalabilidad**: Bases de datos pueden escalar independientemente
- **Resiliencia**: Fallo de una BD no afecta otros servicios

| Servicio | Base de Datos | Puerto |
|----------|---------------|--------|
| Order Service | `order_service_development` | 5433 |
| Customer Service | `customer_service_development` | 5434 |

---

## 3. Especificación 1: Comunicación HTTP entre Microservicios

### 3.1 Objetivo

Implementar comunicación síncrona entre **Order Service** y **Customer Service** para enriquecer las respuestas de órdenes con información del cliente.

### 3.2 Requisitos Funcionales

**RF-HTTP-001**: Order Service DEBE realizar una llamada HTTP GET a Customer Service al crear una orden.

**RF-HTTP-002**: La respuesta DEBE incluir datos del cliente (id, name, email, address).

**RF-HTTP-003**: El sistema DEBE continuar operando si Customer Service no está disponible (graceful degradation).

### 3.3 Implementación Técnica

#### 3.3.1 Cliente HTTP - Faraday

**Ubicación**: `order_service/app/services/customers/client.rb`

**Características**:

```ruby
module Customers
  class Client
    TIMEOUT = 5          # Read timeout en segundos
    OPEN_TIMEOUT = 2     # Connection timeout en segundos
    
    def fetch(customer_id)
      response = connection.get("/customers/#{customer_id}")
      
      case response.status
      when 200
        normalize_response(response.body)
      when 404
        raise NotFoundError
      when 500..599
        raise ServiceError
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise TimeoutError
    end
    
    private
    
    def connection
      @connection ||= Faraday.new(url: base_url) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
        
        conn.options.timeout = TIMEOUT
        conn.options.open_timeout = OPEN_TIMEOUT
        
        conn.headers['Content-Type'] = 'application/json'
        conn.headers['Accept'] = 'application/json'
      end
    end
  end
end
```

#### 3.3.2 Configuración de Timeouts

| Parámetro | Valor | Justificación |
|-----------|-------|---------------|
| `open_timeout` | 2s | Tiempo máximo para establecer conexión TCP |
| `timeout` | 5s | Tiempo máximo para recibir respuesta completa |

**Rationale**: Timeouts conservadores para evitar bloqueos prolongados en comunicación interna.

#### 3.3.3 Manejo de Errores

**Clasificación de Errores**:

| Tipo de Error | Clase | Acción |
|---------------|-------|--------|
| Cliente no encontrado | `NotFoundError` | Retornar 404 |
| Servicio caído | `ServiceError` | Log + continuar sin customer data |
| Timeout de red | `TimeoutError` | Log + continuar sin customer data |

**Estrategia de Resiliencia**:

```ruby
# En Orders::Create service
customer_data = fetch_customer_data(customer_id)
rescue Customers::Client::TimeoutError, 
       Customers::Client::ServiceError => e
  Rails.logger.warn("Customer service unavailable: #{e.message}")
  @warnings << "Customer service unavailable. Customer data not included."
  nil
end
```

**Resultado**: Orden se crea exitosamente (201 Created) con `customer: null` y mensaje de advertencia.

#### 3.3.4 Endpoint de Customer Service

**URL**: `GET /customers/:id`

**Respuesta Exitosa (200 OK)**:

```json
{
  "id": 1,
  "customer_name": "John Doe",
  "address": "123 Main Street, New York, NY 10001, USA",
  "orders_count": 5
}
```

**Respuesta de Error (404 Not Found)**:

```json
{
  "error": "Customer not found"
}
```

### 3.4 Variables de Entorno

```bash
CUSTOMER_SERVICE_URL=http://customer_service:3000
```

**Nota**: En Docker Compose, se usa service discovery por nombre de servicio.

### 3.5 Pruebas de Integración HTTP

**Ubicación**: `order_service/spec/requests/orders_spec.rb`

**Técnica**: HTTP Mocking con WebMock

```ruby
# Mock de respuesta exitosa
stub_request(:get, "#{ENV['CUSTOMER_SERVICE_URL']}/customers/1")
  .to_return(
    status: 200,
    body: customer_service_response.to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

# Mock de timeout
stub_request(:get, "#{ENV['CUSTOMER_SERVICE_URL']}/customers/1")
  .to_timeout
```

**Casos de Prueba**:

- ✅ Llamada HTTP exitosa con datos del cliente
- ✅ Customer Service retorna 404
- ✅ Customer Service retorna 500
- ✅ Timeout de conexión
- ✅ Fallo de red (ConnectionFailed)
- ✅ Orden se crea incluso si Customer Service falla

---

## 4. Especificación 2: Arquitectura Orientada a Eventos

### 4.1 Objetivo

Implementar comunicación asíncrona basada en eventos para actualizar el contador de órdenes (`orders_count`) en Customer Service cuando se crea una nueva orden.

### 4.2 Requisitos Funcionales

**RF-EVENT-001**: Order Service DEBE publicar un evento `order.created.v1` cada vez que se crea una orden.

**RF-EVENT-002**: Customer Service DEBE consumir eventos `order.created` y actualizar `orders_count`.

**RF-EVENT-003**: El procesamiento de eventos DEBE ser idempotente (exactly-once semantics).

**RF-EVENT-004**: Eventos duplicados NO DEBEN incrementar `orders_count` múltiples veces.

**RF-EVENT-005**: Errores permanentes DEBEN enviarse a Dead Letter Queue.

### 4.3 Arquitectura de Mensajería

#### 4.3.1 Topología de RabbitMQ

```
┌─────────────────────────────────────────────────────────┐
│                    RabbitMQ Broker                      │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Exchange: order.events                          │  │
│  │  Type: topic                                     │  │
│  │  Durable: true                                   │  │
│  └────────────────┬─────────────────────────────────┘  │
│                   │                                     │
│                   │ Binding: order.created              │
│                   │                                     │
│                   ▼                                     │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Queue: customer_service.order_created           │  │
│  │  Durable: true                                   │  │
│  │  Arguments:                                      │  │
│  │    x-dead-letter-exchange: dlx.order.events      │  │
│  │    x-dead-letter-routing-key: order.created.dlq  │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  DLX: dlx.order.events                           │  │
│  │  Type: topic                                     │  │
│  │  Durable: true                                   │  │
│  └────────────────┬─────────────────────────────────┘  │
│                   │                                     │
│                   ▼                                     │
│  ┌──────────────────────────────────────────────────┐  │
│  │  DLQ: customer_service.order_created.dlq         │  │
│  │  Durable: true                                   │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

#### 4.3.2 Configuración de RabbitMQ

**Variables de Entorno**:

```bash
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
ORDER_EVENTS_EXCHANGE=order.events
```

**Setup Automatizado**:

```bash
docker-compose exec customer_service rake rabbitmq:setup
```

### 4.4 Publicación de Eventos

#### 4.4.1 Publisher Service

**Ubicación**: `order_service/app/services/events/publish_order_created.rb`

**Estructura del Evento**:

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "occurred_at": "2026-03-09T13:30:00Z",
  "type": "order.created.v1",
  "order": {
    "id": 123,
    "customer_id": 1,
    "product_name": "Laptop Dell XPS 15",
    "quantity": 2,
    "price": "1299.99",
    "status": "pending"
  }
}
```

**Campos del Evento**:

| Campo | Tipo | Descripción | Obligatorio |
|-------|------|-------------|-------------|
| `event_id` | UUID | Identificador único del evento (idempotencia) | Sí |
| `occurred_at` | ISO8601 | Timestamp de ocurrencia del evento | Sí |
| `type` | String | Tipo y versión del evento | Sí |
| `order` | Object | Datos de la orden creada | Sí |

**Propiedades de Publicación**:

```ruby
exchange.publish(
  payload.to_json,
  routing_key: 'order.created',
  persistent: true,              # Mensaje sobrevive restart de RabbitMQ
  content_type: 'application/json',
  timestamp: Time.current.to_i
)
```

#### 4.4.2 Versionado de Eventos

**Estrategia**: Versionado semántico en el campo `type`.

- `order.created.v1`: Versión inicial
- `order.created.v2`: Futuras modificaciones de schema

**Beneficios**:
- Múltiples versiones pueden coexistir
- Consumers pueden migrar gradualmente
- Backward compatibility garantizada

### 4.5 Consumo de Eventos

#### 4.5.1 Consumer Implementation

**Ubicación**: `customer_service/app/consumers/order_created_consumer.rb`

**Características**:

- **Manual ACK**: Control explícito de acknowledgment
- **Prefetch = 1**: Procesa un mensaje a la vez
- **Graceful Shutdown**: Manejo de señales SIGINT/SIGTERM

**Flujo de Procesamiento**:

```
┌─────────────────────────────────────────────────────────┐
│ 1. Recibir mensaje de RabbitMQ                          │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Extraer correlation_id (trazabilidad)                │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Parsear JSON payload                                 │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 4. BEGIN TRANSACTION                                    │
│    ├─ INSERT INTO processed_events (event_id)           │
│    │  (Si ya existe → RecordNotUnique → Skip)           │
│    └─ UPDATE customers SET orders_count += 1            │
│    COMMIT                                               │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 5. ACK mensaje a RabbitMQ                               │
└─────────────────────────────────────────────────────────┘
```

#### 4.5.2 Garantía de Idempotencia

**Tabla de Eventos Procesados**:

```sql
CREATE TABLE processed_events (
  id BIGSERIAL PRIMARY KEY,
  event_id VARCHAR(255) NOT NULL UNIQUE,
  processed_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX index_processed_events_on_event_id 
  ON processed_events (event_id);
```

**Algoritmo de Idempotencia**:

```ruby
ActiveRecord::Base.transaction do
  # Intento de insertar event_id
  ProcessedEvent.create!(
    event_id: event_id, 
    processed_at: Time.current
  )
  
  # Si llegamos aquí, evento es nuevo
  customer.increment!(:orders_count)
  
rescue ActiveRecord::RecordNotUnique
  # Evento ya procesado, skip silenciosamente
  Rails.logger.info("Event #{event_id} already processed")
  return
end
```

**Propiedades ACID**:

- **Atomicidad**: Insert + Update en misma transacción
- **Consistencia**: Constraint UNIQUE garantiza un solo procesamiento
- **Aislamiento**: Nivel de aislamiento READ COMMITTED
- **Durabilidad**: Commit persiste cambios a disco

#### 4.5.3 Clasificación de Errores

**Errores Temporales** (Requeue = true):

```ruby
TEMPORARY_ERRORS = [
  ActiveRecord::ConnectionTimeoutError,
  ActiveRecord::ConnectionNotEstablished,
  PG::ConnectionBad,
  PG::UnableToSend
].freeze
```

**Acción**: `channel.nack(delivery_tag, false, true)` → Mensaje vuelve a la queue

**Errores Permanentes** (Dead Letter Queue):

```ruby
PERMANENT_ERRORS = [
  ActiveRecord::RecordNotFound,      # Customer no existe
  ActiveRecord::RecordInvalid,       # Validación fallida
  JSON::ParserError                  # Payload corrupto
].freeze
```

**Acción**: `channel.nack(delivery_tag, false, false)` → Mensaje va a DLQ

#### 4.5.4 Dead Letter Queue (DLQ)

**Propósito**: Almacenar mensajes que no pueden procesarse para análisis posterior.

**Casos de Uso**:
- Customer ID no existe en base de datos
- Payload JSON malformado
- Violación de constraints de base de datos

**Monitoreo**: Alertas deben configurarse si DLQ tiene mensajes.

**Re-procesamiento**: Mensajes pueden moverse manualmente de DLQ a queue principal después de corregir el problema.

### 4.6 Resiliencia ante Fallo de RabbitMQ

**Estrategia**: Si RabbitMQ no está disponible al publicar evento, Order Service continúa.

```ruby
begin
  Events::PublishOrderCreated.call(order)
rescue StandardError => e
  Rails.logger.error("Failed to publish event: #{e.message}")
  # NO revierte la transacción de la orden
end
```

**Consecuencias**:
- ✅ Orden persiste aunque RabbitMQ esté caído
- ⚠️ Inconsistencia temporal: `orders_count` no se actualiza
- 🔄 Requiere mecanismo de reconciliación (fuera de scope)

### 4.7 Ejecución del Consumer

**Background (Producción)**:

```bash
docker-compose exec -d customer_service rake rabbitmq:consume
```

**Foreground (Desarrollo)**:

```bash
docker-compose exec customer_service rake rabbitmq:consume
```

**Verificación**:

```bash
docker-compose exec customer_service ps aux | grep rabbitmq
```

---

## 5. Especificación 3: Suite de Pruebas

### 5.1 Objetivo

Garantizar la calidad del código mediante pruebas automatizadas que cubran:
- Creación y consulta de pedidos
- Integración HTTP entre servicios
- Generación y consumo de eventos
- Idempotencia
- Manejo de errores

### 5.2 Framework de Testing

**RSpec 3.x** con las siguientes extensiones:

| Gema | Propósito |
|------|-----------|
| `rspec-rails` | Integración con Rails |
| `factory_bot_rails` | Factories para fixtures |
| `webmock` | Mocking de llamadas HTTP |
| `database_cleaner` | Limpieza de BD entre tests |

### 5.3 Order Service - Suite de Pruebas

#### 5.3.1 Request Specs - Orders API

**Ubicación**: `order_service/spec/requests/orders_spec.rb`

**Cobertura**: 331 líneas, 25+ casos de prueba

**Categorías de Tests**:

##### A. Creación Exitosa de Órdenes

```ruby
describe "POST /orders" do
  context "when the request is valid" do
    it "creates an order"
    it "returns status 201 created"
    it "returns the created order with customer data"
    it "publishes order.created event to RabbitMQ"
    it "makes HTTP request to Customer Service"
  end
end
```

**Técnicas**:
- Mock de Customer Service con WebMock
- Mock de RabbitMQ publisher con RSpec doubles
- Verificación de cambios en BD con `expect { }.to change(Order, :count)`

##### B. Resiliencia ante Fallos

```ruby
context "when Customer Service is unavailable" do
  before do
    stub_request(:get, /customers/).to_timeout
  end
  
  it "still creates the order"
  it "returns 201 with customer as null"
  it "includes a warning message"
end

context "when RabbitMQ publishing fails" do
  before do
    allow(Events::PublishOrderCreated)
      .to receive(:call)
      .and_raise(StandardError)
  end
  
  it "still creates the order and returns 201"
  it "logs the error but doesn't fail the request"
end
```

##### C. Validaciones

```ruby
context "when required fields are missing" do
  it "returns 422 when customer_id is missing"
  it "returns 422 when product_name is missing"
  it "returns 422 when quantity is missing"
  it "returns 422 when price is missing"
end

context "when quantity is invalid" do
  it "returns 422 when quantity is zero"
  it "returns 422 when quantity is negative"
end

context "when price is invalid" do
  it "returns 422 when price is negative"
  it "accepts price of zero"
end
```

##### D. Consulta de Órdenes

```ruby
describe "GET /orders" do
  context "when customer_id parameter is provided" do
    it "returns only orders for the specified customer"
    it "returns orders sorted by created_at descending"
    it "returns empty array when customer has no orders"
    it "does not return orders from other customers"
  end
  
  context "when customer_id parameter is missing" do
    it "returns 400 bad request"
    it "returns error message"
  end
end
```

#### 5.3.2 Service Specs

**Ubicación**: `order_service/spec/services/`

- `orders/create_spec.rb`: Tests del service object de orquestación
- `events/publish_order_created_spec.rb`: Tests de publicación de eventos

### 5.4 Customer Service - Suite de Pruebas

#### 5.4.1 Consumer Specs

**Ubicación**: `customer_service/spec/consumers/order_created_consumer_spec.rb`

**Cobertura**: 329 líneas, 20+ casos de prueba

**Categorías de Tests**:

##### A. Procesamiento Exitoso

```ruby
describe "#process_message" do
  context "when processing a valid event" do
    it "increments the customer's orders_count"
    it "creates a processed_event record"
    it "stores the correct event_id in processed_events"
    it "acknowledges the message"
    it "logs the successful processing"
  end
end
```

##### B. Idempotencia

```ruby
context "idempotency - when the same event is processed twice" do
  before do
    # Procesar evento una vez
    consumer.send(:process_message, delivery_info, properties, payload)
  end
  
  it "does not increment orders_count again"
  it "does not create another processed_event record"
  it "still acknowledges the message"
  it "logs that the event was already processed"
end
```

**Verificación**: `orders_count` permanece en 1 después de procesar el mismo `event_id` dos veces.

##### C. Manejo de Errores Permanentes

```ruby
context "when customer does not exist" do
  it "does not create a processed_event record"
  it "sends NACK without requeue (to Dead Letter Queue)"
  it "logs the error as permanent"
  it "does not increment any customer's orders_count"
end

context "when payload is invalid JSON" do
  it "sends NACK without requeue (permanent error)"
  it "logs the error"
  it "does not create a processed_event"
end
```

##### D. Manejo de Errores Temporales

```ruby
context "when database connection fails (temporary error)" do
  before do
    allow(ProcessedEvent).to receive(:create!)
      .and_raise(ActiveRecord::ConnectionTimeoutError)
  end
  
  it "sends NACK with requeue"
  it "logs the temporary error"
  it "does not increment orders_count"
end
```

##### E. Atomicidad de Transacciones

```ruby
context "transaction atomicity" do
  it "creates processed_event and increments orders_count in same transaction"
  
  it "rolls back both operations if processed_event creation fails" do
    allow(ProcessedEvent).to receive(:create!)
      .and_raise(ActiveRecord::RecordInvalid)
    
    expect {
      consumer.send(:process_message, ...)
    }.not_to change { customer.reload.orders_count }
  end
end
```

##### F. Múltiples Eventos

```ruby
context "multiple events for the same customer" do
  it "increments orders_count for each unique event"
  it "creates separate processed_event records"
end
```

#### 5.4.2 Request Specs

**Ubicación**: `customer_service/spec/requests/customers_spec.rb`

- Tests del endpoint `GET /customers/:id`
- Verificación de respuesta con `orders_count`

### 5.5 Factories

**FactoryBot** para generación de datos de prueba:

```ruby
# order_service/spec/factories/orders.rb
FactoryBot.define do
  factory :order do
    customer_id { 1 }
    product_name { "Laptop Dell XPS 15" }
    quantity { 2 }
    price { 1299.99 }
    status { "pending" }
  end
end

# customer_service/spec/factories/customers.rb
FactoryBot.define do
  factory :customer do
    customer_name { "John Doe" }
    address { "123 Main Street, New York, NY" }
    orders_count { 0 }
  end
end
```

### 5.6 Ejecución de Tests

#### 5.6.1 Comandos

```bash
# Order Service - Todos los tests
docker-compose exec order_service bundle exec rspec

# Order Service - Request specs
docker-compose exec order_service bundle exec rspec spec/requests

# Order Service - Service specs
docker-compose exec order_service bundle exec rspec spec/services

# Customer Service - Todos los tests
docker-compose exec customer_service bundle exec rspec

# Customer Service - Consumer specs
docker-compose exec customer_service bundle exec rspec spec/consumers

# Con formato detallado
docker-compose exec order_service bundle exec rspec --format documentation
```

#### 5.6.2 Test específico

```bash
# Archivo completo
docker-compose exec order_service bundle exec rspec spec/requests/orders_spec.rb

# Test específico por línea
docker-compose exec order_service bundle exec rspec spec/requests/orders_spec.rb:45
```

### 5.7 Cobertura de Código

**Objetivo**: >90% de cobertura en lógica de negocio

**Áreas Críticas**:
- ✅ Controllers (100%)
- ✅ Service Objects (100%)
- ✅ Consumers (100%)
- ✅ Models (validaciones y callbacks)

### 5.8 Smoke Test End-to-End

**Ubicación**: `scripts/smoke_e2e.sh`

**Propósito**: Verificar integración completa del sistema

**Flujo**:
1. Levantar docker-compose
2. Health checks de servicios
3. Setup de bases de datos
4. Setup de RabbitMQ
5. Iniciar consumer
6. Crear orden vía API
7. Verificar incremento de `orders_count` (con retries)

**Ejecución**:

```bash
chmod +x scripts/smoke_e2e.sh
./scripts/smoke_e2e.sh
```

**Tiempo estimado**: 1-2 minutos

---

## 6. Especificación 4: Documentación del Sistema

### 6.1 Objetivo

Proveer documentación completa y actualizada para:
- Configuración y ejecución de servicios
- Ejecución de pruebas
- Arquitectura y flujos del sistema
- Comandos útiles de desarrollo

### 6.2 Documentos Principales

#### 6.2.1 README.md

**Ubicación**: `README.md` (627 líneas)

**Contenido**:

| Sección | Descripción |
|---------|-------------|
| Descripción del Proyecto | Overview de arquitectura y servicios |
| Diagrama Mermaid | Secuencia completa del flujo de creación de orden |
| Setup Local | Instrucciones paso a paso para levantar el sistema |
| Ejecución de Tests | Comandos para correr suite de pruebas |
| Decisiones de Arquitectura | ADRs (Architecture Decision Records) |
| APIs | Documentación de endpoints con ejemplos curl |
| Monitoreo | Logs, métricas, RabbitMQ Management UI |
| Desarrollo | Comandos para agregar gems, migraciones, console |

**Diagrama de Arquitectura**:

Incluye diagrama Mermaid de secuencia que muestra:
- Cliente → Order Service
- Order Service → Customer Service (HTTP)
- Order Service → RabbitMQ (Publish)
- RabbitMQ → Consumer
- Consumer → Base de datos (Transaction)
- Manejo de errores y resiliencia

#### 6.2.2 COMANDOS_UTILES.md

**Ubicación**: `COMANDOS_UTILES.md` (350 líneas)

**Contenido**:

- **Iniciar el Proyecto**: docker-compose up, rebuild
- **Monitoreo y Estado**: logs, ps, stats
- **Gestión de Bases de Datos**: create, migrate, seed, reset, console
- **RabbitMQ**: setup, consume, management UI
- **Testing**: rspec con diferentes opciones
- **Pruebas Manuales de API**: curl/PowerShell ejemplos
- **Desarrollo**: instalar gems, migraciones, bash access
- **Limpieza**: down, volumes, images
- **Métricas y Monitoreo**: contadores, recursos
- **Debugging**: conectividad, configuración

#### 6.2.3 DOCKER_SETUP.md

**Ubicación**: `DOCKER_SETUP.md`

**Contenido**:
- Configuración detallada de docker-compose.yml
- Explicación de servicios y volúmenes
- Networking entre contenedores
- Variables de entorno

#### 6.2.4 SMOKE_TEST.md

**Ubicación**: `SMOKE_TEST.md`

**Contenido**:
- Documentación del script de smoke test E2E
- Casos de prueba cubiertos
- Interpretación de resultados
- Troubleshooting

#### 6.2.5 IMPROVEMENTS.md

**Ubicación**: `IMPROVEMENTS.md` (502 líneas)

**Contenido**:
- Mejoras propuestas para producción
- Logging estructurado
- Request ID tracking
- Timeouts y reintentos
- Seguridad
- Health checks mejorados
- Priorización y esfuerzo estimado

### 6.3 Documentación de APIs

#### 6.3.1 Order Service API

**Base URL**: `http://localhost:3001`

**Endpoints**:

##### POST /orders

Crea una nueva orden.

**Request**:

```bash
curl -X POST http://localhost:3001/orders \
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

**Response (201 Created)**:

```json
{
  "id": 1,
  "customer_id": 1,
  "product_name": "Laptop Dell XPS 15",
  "quantity": 2,
  "price": "1299.99",
  "status": "pending",
  "created_at": "2026-03-09T13:00:00Z",
  "updated_at": "2026-03-09T13:00:00Z",
  "customer": {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "address": "123 Main Street, New York, NY 10001, USA"
  }
}
```

**Validaciones**:

| Campo | Regla |
|-------|-------|
| `customer_id` | Requerido, numérico |
| `product_name` | Requerido, string |
| `quantity` | Requerido, > 0 |
| `price` | Requerido, >= 0 |

##### GET /orders?customer_id=:id

Lista órdenes de un cliente.

**Request**:

```bash
curl http://localhost:3001/orders?customer_id=1
```

**Response (200 OK)**:

```json
[
  {
    "id": 1,
    "customer_id": 1,
    "product_name": "Laptop Dell XPS 15",
    "quantity": 2,
    "price": "1299.99",
    "status": "pending",
    "created_at": "2026-03-09T13:00:00Z",
    "updated_at": "2026-03-09T13:00:00Z"
  }
]
```

**Ordenamiento**: Por `created_at` descendente

#### 6.3.2 Customer Service API

**Base URL**: `http://localhost:3002`

##### GET /customers/:id

Obtiene información de un cliente.

**Request**:

```bash
curl http://localhost:3002/customers/1
```

**Response (200 OK)**:

```json
{
  "id": 1,
  "customer_name": "John Doe",
  "address": "123 Main Street, New York, NY 10001, USA",
  "orders_count": 5
}
```

**Response (404 Not Found)**:

```json
{
  "error": "Customer not found"
}
```

### 6.4 Diagramas de Arquitectura

#### 6.4.1 Diagrama de Secuencia (Mermaid)

Incluido en `README.md`, muestra:
- Flujo completo de creación de orden
- Comunicación HTTP síncrona
- Publicación de eventos
- Consumo asíncrono
- Manejo de errores
- Transacciones de base de datos

#### 6.4.2 Diagrama de Componentes

```
┌─────────────────────────────────────────────────────────┐
│                    Order Service                        │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Orders      │  │  Customers   │  │  Events      │  │
│  │  Controller  │  │  Client      │  │  Publisher   │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                 │          │
│         ▼                 ▼                 ▼          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Orders::    │  │  Faraday     │  │  Bunny       │  │
│  │  Create      │  │  HTTP        │  │  AMQP        │  │
│  └──────┬───────┘  └──────────────┘  └──────────────┘  │
│         │                                               │
│         ▼                                               │
│  ┌──────────────┐                                       │
│  │  Order       │                                       │
│  │  Model       │                                       │
│  └──────────────┘                                       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                  Customer Service                       │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │  Customers   │  │  OrderCreated│                     │
│  │  Controller  │  │  Consumer    │                     │
│  └──────┬───────┘  └──────┬───────┘                     │
│         │                 │                             │
│         ▼                 ▼                             │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │  Customer    │  │  Processed   │                     │
│  │  Model       │  │  Event Model │                     │
│  └──────────────┘  └──────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

### 6.5 Instrucciones de Setup

Documentadas en `README.md` con comandos paso a paso:

1. **Levantar servicios**: `docker-compose up -d`
2. **Setup de DBs**: `rails db:create && rails db:migrate && rails db:seed`
3. **Setup de RabbitMQ**: `rake rabbitmq:setup`
4. **Iniciar consumer**: `rake rabbitmq:consume`
5. **Verificar health**: `curl http://localhost:3001/health`

### 6.6 Troubleshooting

Incluido en documentación:

- Verificar logs: `docker-compose logs -f service_name`
- Verificar conectividad: `curl http://service:port/health`
- Resetear sistema: `docker-compose down -v && docker-compose up -d`
- Acceder a RabbitMQ UI: `http://localhost:15672`

---

## 7. Requisitos No Funcionales

### 7.1 Performance

**RNF-PERF-001**: Las llamadas HTTP entre servicios DEBEN completarse en <100ms (p95) en red local.

**RNF-PERF-002**: El procesamiento de eventos DEBE soportar al menos 100 eventos/segundo.

**RNF-PERF-003**: El tiempo de respuesta de `POST /orders` DEBE ser <500ms (p95).

### 7.2 Disponibilidad

**RNF-AVAIL-001**: Order Service DEBE continuar operando si Customer Service está caído (graceful degradation).

**RNF-AVAIL-002**: Order Service DEBE continuar operando si RabbitMQ está caído.

**RNF-AVAIL-003**: Consumer DEBE reconectarse automáticamente a RabbitMQ si la conexión se pierde.

### 7.3 Escalabilidad

**RNF-SCALE-001**: Cada servicio DEBE poder escalar horizontalmente de forma independiente.

**RNF-SCALE-002**: Consumer DEBE soportar múltiples instancias concurrentes sin duplicar procesamiento (idempotencia).

**RNF-SCALE-003**: Bases de datos DEBEN poder escalar independientemente por servicio.

### 7.4 Seguridad

**RNF-SEC-001**: Comunicación entre servicios en producción DEBE usar HTTPS/TLS.

**RNF-SEC-002**: RabbitMQ en producción DEBE usar autenticación y vhost dedicado.

**RNF-SEC-003**: Credenciales DEBEN almacenarse en variables de entorno, nunca en código.

### 7.5 Observabilidad

**RNF-OBS-001**: Todos los servicios DEBEN exponer endpoint `/health` para health checks.

**RNF-OBS-002**: Logs DEBEN incluir correlation_id para trazabilidad end-to-end.

**RNF-OBS-003**: Eventos DEBEN incluir `event_id` único para debugging.

**RNF-OBS-004**: Dead Letter Queue DEBE monitorearse con alertas.

### 7.6 Mantenibilidad

**RNF-MAINT-001**: Código DEBE seguir convenciones de Rails (Service Objects, RESTful routes).

**RNF-MAINT-002**: Cobertura de tests DEBE ser >90% en lógica de negocio.

**RNF-MAINT-003**: Documentación DEBE actualizarse con cada cambio de API o arquitectura.

---

## 8. Decisiones de Diseño

### 8.1 ADR-001: Idempotencia con Tabla `processed_events`

**Contexto**: RabbitMQ garantiza at-least-once delivery, lo que puede resultar en mensajes duplicados.

**Decisión**: Implementar tabla `processed_events` con constraint UNIQUE en `event_id`.

**Alternativas Consideradas**:
- Redis con TTL para tracking de eventos
- Idempotency key en headers HTTP

**Consecuencias**:
- ✅ Garantía de exactly-once processing a nivel de aplicación
- ✅ Funciona incluso con reentregas de RabbitMQ
- ✅ Transacción atómica: insert + update
- ⚠️ Requiere limpieza periódica de eventos antiguos (opcional)

### 8.2 ADR-002: Graceful Degradation ante Fallo de Customer Service

**Contexto**: No queremos que la caída de Customer Service bloquee creación de órdenes.

**Decisión**: Continuar creación de orden (201 Created) con `customer: null` y warning.

**Alternativas Consideradas**:
- Retornar 503 Service Unavailable
- Cachear datos de clientes en Order Service

**Consecuencias**:
- ✅ Alta disponibilidad de Order Service
- ✅ Eventual consistency: customer data puede obtenerse después
- ✅ Transparencia: warning informa al cliente
- ⚠️ Cliente recibe respuesta incompleta pero válida

### 8.3 ADR-003: No Revertir Orden si RabbitMQ Falla

**Contexto**: La orden es el recurso principal; eventos son notificaciones secundarias.

**Decisión**: Si RabbitMQ falla, loggear error pero NO revertir transacción de orden.

**Alternativas Consideradas**:
- Revertir orden si evento no se publica
- Implementar outbox pattern para garantizar publicación

**Consecuencias**:
- ✅ Orden persiste aunque RabbitMQ esté caído
- ✅ No bloqueamos operaciones de negocio
- ⚠️ Inconsistencia temporal: orden creada pero evento no enviado
- 🔄 Requiere mecanismo de reconciliación (fuera de scope actual)

### 8.4 ADR-004: Versionado de Eventos con Campo `type`

**Contexto**: Schema de eventos evolucionará con el tiempo.

**Decisión**: Usar campo `type` con versión semántica (ej: `order.created.v1`).

**Alternativas Consideradas**:
- Versionado en routing key
- Exchanges separados por versión

**Consecuencias**:
- ✅ Múltiples versiones pueden coexistir
- ✅ Consumers pueden migrar gradualmente
- ✅ Backward compatibility
- ⚠️ Requiere documentación de schema por versión

### 8.5 ADR-005: Customer No Existe → Dead Letter Queue

**Contexto**: Evento referencia customer_id que no existe en base de datos.

**Decisión**: Enviar mensaje a DLQ (error permanente), no crear customer automáticamente.

**Alternativas Consideradas**:
- Crear customer automáticamente con datos mínimos
- Ignorar silenciosamente el evento

**Consecuencias**:
- ✅ Respeta bounded context (Customer Service es owner)
- ✅ Visibilidad del problema vía DLQ
- ✅ Permite análisis y re-procesamiento manual
- ⚠️ Requiere monitoreo de DLQ

### 8.6 ADR-006: Database per Service Pattern

**Contexto**: Microservicios deben ser independientes y escalables.

**Decisión**: Cada servicio tiene su propia base de datos PostgreSQL.

**Alternativas Consideradas**:
- Base de datos compartida con schemas separados
- Base de datos compartida con prefijos de tabla

**Consecuencias**:
- ✅ Autonomía completa de servicios
- ✅ Escalabilidad independiente
- ✅ Resiliencia: fallo de una BD no afecta otros servicios
- ⚠️ No hay joins entre servicios (requiere comunicación HTTP/eventos)
- ⚠️ Eventual consistency entre servicios

---

## 9. Apéndices

### 9.1 Glosario

| Término | Definición |
|---------|------------|
| **ACK** | Acknowledgment - Confirmación de procesamiento exitoso de mensaje |
| **AMQP** | Advanced Message Queuing Protocol - Protocolo de mensajería |
| **Bounded Context** | Límite explícito de un modelo de dominio en DDD |
| **DLQ** | Dead Letter Queue - Cola para mensajes no procesables |
| **Exactly-Once** | Garantía de procesamiento de mensaje una sola vez |
| **Graceful Degradation** | Continuar operando con funcionalidad reducida ante fallos |
| **Idempotencia** | Propiedad donde múltiples ejecuciones producen el mismo resultado |
| **NACK** | Negative Acknowledgment - Rechazo de mensaje |
| **Routing Key** | Clave para enrutar mensajes a queues específicas |
| **Service Object** | Patrón de diseño para encapsular lógica de negocio |

### 9.2 Referencias

- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [Faraday HTTP Client](https://lostisland.github.io/faraday/)
- [RSpec Testing Framework](https://rspec.info/)
- [Rails API-Only Applications](https://guides.rubyonrails.org/api_app.html)
- [Microservices Patterns - Chris Richardson](https://microservices.io/patterns/)

### 9.3 Variables de Entorno

#### Order Service

```bash
# Customer Service URL
CUSTOMER_SERVICE_URL=http://customer_service:3000

# RabbitMQ Configuration
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
ORDER_EVENTS_EXCHANGE=order.events

# Database
DATABASE_HOST=postgres_order
DATABASE_PORT=5432
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
DATABASE_NAME=order_service_development
```

#### Customer Service

```bash
# RabbitMQ Configuration
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
RABBITMQ_VHOST=/
ORDER_EVENTS_EXCHANGE=order.events

# Database
DATABASE_HOST=postgres_customer
DATABASE_PORT=5432
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
DATABASE_NAME=customer_service_development
```

### 9.4 Puertos Expuestos

| Servicio | Puerto Interno | Puerto Externo | Protocolo |
|----------|----------------|----------------|-----------|
| Order Service | 3000 | 3001 | HTTP |
| Customer Service | 3000 | 3002 | HTTP |
| PostgreSQL Order | 5432 | 5433 | PostgreSQL |
| PostgreSQL Customer | 5432 | 5434 | PostgreSQL |
| RabbitMQ AMQP | 5672 | 5672 | AMQP |
| RabbitMQ Management | 15672 | 15672 | HTTP |

### 9.5 Comandos de Verificación

```bash
# Health checks
curl http://localhost:3001/health
curl http://localhost:3002/health

# RabbitMQ Management UI
open http://localhost:15672  # guest/guest

# Verificar órdenes creadas
docker-compose exec order_service rails runner "puts Order.count"

# Verificar eventos procesados
docker-compose exec customer_service rails runner "puts ProcessedEvent.count"

# Verificar orders_count
docker-compose exec customer_service rails runner "puts Customer.find(1).orders_count"

# Logs en tiempo real
docker-compose logs -f order_service
docker-compose logs -f customer_service
docker-compose logs -f rabbitmq
```

---

**Fin del Documento**
