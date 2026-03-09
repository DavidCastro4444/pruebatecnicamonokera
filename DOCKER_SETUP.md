# Docker Setup - Rails Microservices Monorepo

## Servicios Incluidos

- **order_service** - Puerto 3001
- **customer_service** - Puerto 3002
- **postgres_order** - Puerto 5433
- **postgres_customer** - Puerto 5434
- **rabbitmq** - Puerto 5672 (AMQP), 15672 (Management UI)

## Comandos Básicos

### Levantar Todos los Servicios

```bash
docker-compose up -d
```

### Ver Logs

```bash
# Todos los servicios
docker-compose logs -f

# Servicio específico
docker-compose logs -f order_service
docker-compose logs -f customer_service
docker-compose logs -f rabbitmq
```

### Detener Servicios

```bash
docker-compose down
```

### Detener y Eliminar Volúmenes (Reset Completo)

```bash
docker-compose down -v
```

## Setup Inicial - Migraciones y Seeds

### Order Service

```bash
# Crear base de datos
docker-compose exec order_service rails db:create

# Ejecutar migraciones
docker-compose exec order_service rails db:migrate

# (Opcional) Ejecutar seeds si los tienes
docker-compose exec order_service rails db:seed
```

### Customer Service

```bash
# Crear base de datos
docker-compose exec customer_service rails db:create

# Ejecutar migraciones
docker-compose exec customer_service rails db:migrate

# Ejecutar seeds (5 clientes predefinidos)
docker-compose exec customer_service rails db:seed
```

### Setup Completo en Un Solo Comando

```bash
# Order Service
docker-compose exec order_service bash -c "rails db:create && rails db:migrate"

# Customer Service
docker-compose exec customer_service bash -c "rails db:create && rails db:migrate && rails db:seed"
```

## RabbitMQ Setup

### Setup de Exchanges y Queues

```bash
docker-compose exec customer_service rake rabbitmq:setup
```

### Iniciar Consumer (en background)

```bash
docker-compose exec -d customer_service rake rabbitmq:consume
```

O ejecutar en foreground para ver logs:

```bash
docker-compose exec customer_service rake rabbitmq:consume
```

## Acceso a Servicios

### APIs

- **Order Service:** http://localhost:3001
  - Health: http://localhost:3001/health
  - Create Order: POST http://localhost:3001/orders
  - List Orders: GET http://localhost:3001/orders?customer_id=1

- **Customer Service:** http://localhost:3002
  - Health: http://localhost:3002/health
  - Get Customer: GET http://localhost:3002/customers/1

### RabbitMQ Management UI

- **URL:** http://localhost:15672
- **Usuario:** guest
- **Password:** guest

### PostgreSQL

Conectar desde host:

```bash
# Order Service DB
psql -h localhost -p 5433 -U postgres -d order_service_development

# Customer Service DB
psql -h localhost -p 5434 -U postgres -d customer_service_development
```

## Testing End-to-End

### 1. Verificar Health de Servicios

```bash
curl http://localhost:3001/health
curl http://localhost:3002/health
```

### 2. Crear Orden (Trigger Evento)

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

### 3. Verificar Customer Orders Count

```bash
curl http://localhost:3002/customers/1
```

Debería mostrar `orders_count: 1` (incrementado por el consumer)

### 4. Verificar RabbitMQ

Acceder a http://localhost:15672 y ver:
- Exchange: `order.events`
- Queue: `customer_service.order_created`
- Mensajes procesados

## Comandos Útiles

### Rails Console

```bash
# Order Service
docker-compose exec order_service rails console

# Customer Service
docker-compose exec customer_service rails console
```

### Ejecutar Comandos Arbitrarios

```bash
docker-compose exec order_service <comando>
docker-compose exec customer_service <comando>
```

### Rebuild de Imágenes

```bash
docker-compose build
docker-compose up -d
```

### Ver Estado de Servicios

```bash
docker-compose ps
```

## Troubleshooting

### Servicios no inician

```bash
# Ver logs detallados
docker-compose logs order_service
docker-compose logs customer_service

# Verificar healthchecks
docker-compose ps
```

### Base de datos no conecta

```bash
# Verificar que PostgreSQL esté healthy
docker-compose ps postgres_order
docker-compose ps postgres_customer

# Recrear base de datos
docker-compose exec order_service rails db:drop db:create db:migrate
```

### RabbitMQ no recibe mensajes

```bash
# Verificar que RabbitMQ esté corriendo
docker-compose ps rabbitmq

# Verificar logs
docker-compose logs rabbitmq

# Re-setup de infraestructura
docker-compose exec customer_service rake rabbitmq:setup
```

### Reset Completo

```bash
# Detener todo y eliminar volúmenes
docker-compose down -v

# Levantar de nuevo
docker-compose up -d

# Re-ejecutar migraciones y seeds
docker-compose exec order_service bash -c "rails db:create && rails db:migrate"
docker-compose exec customer_service bash -c "rails db:create && rails db:migrate && rails db:seed"
docker-compose exec customer_service rake rabbitmq:setup
```

## Desarrollo Local

Los volúmenes están montados para desarrollo:
- Cambios en código se reflejan automáticamente (con Spring/Bootsnap)
- No necesitas rebuild para cambios de código
- Solo rebuild si cambias Gemfile o Dockerfile

```bash
# Si cambias Gemfile
docker-compose exec order_service bundle install
docker-compose restart order_service
```

## Producción

Para producción, modifica:
1. Cambiar `RAILS_ENV` a `production`
2. Usar secrets para passwords (no hardcodear)
3. Configurar volúmenes persistentes apropiados
4. Agregar nginx como reverse proxy
5. Configurar logging centralizado
6. Usar Docker secrets o variables de entorno seguras

## Variables de Entorno

Todas las variables están configuradas en `docker-compose.yml`:

- **DB_HOST** - Hostname del PostgreSQL
- **DB_PORT** - Puerto de PostgreSQL (5432 interno)
- **DB_USERNAME** - Usuario de base de datos
- **DB_PASSWORD** - Password de base de datos
- **DB_NAME** - Nombre de la base de datos
- **CUSTOMER_SERVICE_URL** - URL interna del customer service
- **RABBITMQ_HOST** - Hostname de RabbitMQ
- **RABBITMQ_PORT** - Puerto de RabbitMQ (5672)
- **RABBITMQ_USERNAME** - Usuario de RabbitMQ
- **RABBITMQ_PASSWORD** - Password de RabbitMQ

Todas las comunicaciones entre servicios usan la red interna `microservices_network`.
