# Guía de Migraciones y Seeds - Rails Microservices Monorepo

Esta guía documenta todas las migraciones y seeds de la base de datos para ambos microservicios.

---

## Tabla de Contenidos

- [Order Service](#order-service)
  - [Migraciones](#migraciones-order-service)
  - [Seeds](#seeds-order-service)
- [Customer Service](#customer-service)
  - [Migraciones](#migraciones-customer-service)
  - [Seeds](#seeds-customer-service)
- [Scripts de Utilidad](#scripts-de-utilidad)
- [Comandos Comunes](#comandos-comunes)

---

## Order Service

### Migraciones Order Service

#### 1. CreateOrders (20260308181906)

**Ubicación:** `order_service/db/migrate/20260308181906_create_orders.rb`

**Propósito:** Crear la tabla `orders` para almacenar las órdenes de compra.

**Estructura:**
```ruby
create_table :orders do |t|
  t.integer :customer_id, null: false
  t.string :product_name, null: false
  t.integer :quantity, null: false
  t.decimal :price, precision: 10, scale: 2, null: false
  t.string :status, default: 'pending'
  t.timestamps
end

add_index :orders, :customer_id
add_index :orders, :status
add_index :orders, :created_at
```

**Campos:**
- `customer_id` (integer, not null): ID del cliente que realizó la orden
- `product_name` (string, not null): Nombre del producto
- `quantity` (integer, not null): Cantidad de productos
- `price` (decimal, not null): Precio unitario (10 dígitos, 2 decimales)
- `status` (string): Estado de la orden (default: 'pending')
- `created_at`, `updated_at`: Timestamps automáticos

**Índices:**
- `customer_id`: Para búsquedas rápidas por cliente
- `status`: Para filtrar órdenes por estado
- `created_at`: Para ordenamiento temporal

**Ejecutar:**
```bash
docker compose exec order_service bundle exec rails db:migrate
```

**Revertir:**
```bash
docker compose exec order_service bundle exec rails db:rollback
```

---

### Seeds Order Service

**Ubicación:** `order_service/db/seeds.rb`

**Estado Actual:** No hay seeds definidos para Order Service.

**Razón:** Las órdenes se crean dinámicamente a través de la API. Los datos de prueba se generan en los tests usando FactoryBot.

**Crear Seeds Manualmente (Opcional):**

Si deseas agregar órdenes de prueba, puedes crear el archivo:

```ruby
# order_service/db/seeds.rb

puts "Seeding orders..."

# Crear órdenes de ejemplo para diferentes clientes
[
  { customer_id: 1, product_name: "Laptop Dell XPS 15", quantity: 1, price: 1299.99 },
  { customer_id: 1, product_name: "Mouse Logitech MX Master", quantity: 2, price: 99.99 },
  { customer_id: 2, product_name: "Monitor LG 27 inch", quantity: 1, price: 349.99 },
  { customer_id: 3, product_name: "Keyboard Mechanical RGB", quantity: 1, price: 149.99 },
  { customer_id: 4, product_name: "Webcam Logitech C920", quantity: 3, price: 79.99 },
  { customer_id: 5, product_name: "Headphones Sony WH-1000XM4", quantity: 1, price: 349.99 }
].each do |order_attrs|
  Order.create!(order_attrs)
end

puts "Created #{Order.count} orders"
```

**Ejecutar:**
```bash
docker compose exec order_service bundle exec rails db:seed
```

---

## Customer Service

### Migraciones Customer Service

#### 1. CreateCustomers (20260308183138)

**Ubicación:** `customer_service/db/migrate/20260308183138_create_customers.rb`

**Propósito:** Crear la tabla `customers` para almacenar información de clientes.

**Estructura:**
```ruby
create_table :customers do |t|
  t.string :customer_name, null: false
  t.string :address
  t.integer :orders_count, default: 0, null: false
  t.timestamps
end

add_index :customers, :customer_name
```

**Campos:**
- `customer_name` (string, not null): Nombre del cliente
- `address` (string): Dirección del cliente
- `orders_count` (integer, default: 0): Contador de órdenes (actualizado por eventos)
- `created_at`, `updated_at`: Timestamps automáticos

**Índices:**
- `customer_name`: Para búsquedas por nombre

**Ejecutar:**
```bash
docker compose exec customer_service bundle exec rails db:migrate
```

---

#### 2. CreateProcessedEvents (20260308183524)

**Ubicación:** `customer_service/db/migrate/20260308183524_create_processed_events.rb`

**Propósito:** Crear la tabla `processed_events` para garantizar idempotencia en el procesamiento de eventos de RabbitMQ.

**Estructura:**
```ruby
create_table :processed_events do |t|
  t.string :event_id, null: false
  t.datetime :processed_at, null: false
  t.timestamps
end

add_index :processed_events, :event_id, unique: true
```

**Campos:**
- `event_id` (string, not null, unique): ID único del evento procesado
- `processed_at` (datetime, not null): Timestamp de cuándo se procesó
- `created_at`, `updated_at`: Timestamps automáticos

**Índices:**
- `event_id` (UNIQUE): Garantiza que un evento solo se procese una vez

**Patrón de Diseño:** 
Este patrón implementa **idempotencia** para evitar procesamiento duplicado de eventos cuando RabbitMQ reentrega mensajes.

**Ejecutar:**
```bash
docker compose exec customer_service bundle exec rails db:migrate
```

---

### Seeds Customer Service

**Ubicación:** `customer_service/db/seeds.rb`

**Propósito:** Crear clientes de prueba para desarrollo y testing.

**Contenido Actual:**
```ruby
puts "Seeding customers..."

customers_data = [
  {
    customer_name: "John Doe",
    address: "123 Main Street, New York, NY 10001, USA"
  },
  {
    customer_name: "Jane Smith",
    address: "456 Oak Avenue, Los Angeles, CA 90001, USA"
  },
  {
    customer_name: "Bob Johnson",
    address: "789 Pine Road, Chicago, IL 60601, USA"
  },
  {
    customer_name: "Alice Williams",
    address: "321 Elm Street, Houston, TX 77001, USA"
  },
  {
    customer_name: "Charlie Brown",
    address: "654 Maple Drive, Phoenix, AZ 85001, USA"
  }
]

customers_data.each do |customer_attrs|
  Customer.create!(customer_attrs)
end

puts "Created #{Customer.count} customers"
```

**Clientes Creados:**
1. **John Doe** (ID: 1) - New York
2. **Jane Smith** (ID: 2) - Los Angeles
3. **Bob Johnson** (ID: 3) - Chicago
4. **Alice Williams** (ID: 4) - Houston
5. **Charlie Brown** (ID: 5) - Phoenix

**Ejecutar:**
```bash
docker compose exec customer_service bundle exec rails db:seed
```

**Verificar:**
```bash
docker compose exec customer_service bundle exec rails runner "puts Customer.all.pluck(:id, :customer_name)"
```

---

## Scripts de Utilidad

### Script: Reset Completo de Bases de Datos

Crear archivo: `scripts/reset_databases.sh`

```bash
#!/bin/bash

echo "Resetting databases..."

echo "Order Service..."
docker compose exec order_service bundle exec rails db:drop
docker compose exec order_service bundle exec rails db:create
docker compose exec order_service bundle exec rails db:migrate

echo "Customer Service..."
docker compose exec customer_service bundle exec rails db:drop
docker compose exec customer_service bundle exec rails db:create
docker compose exec customer_service bundle exec rails db:migrate
docker compose exec customer_service bundle exec rails db:seed

echo "Databases reset complete!"
echo ""
echo "Database Status:"
docker compose exec order_service bundle exec rails runner "puts 'Orders: ' + Order.count.to_s"
docker compose exec customer_service bundle exec rails runner "puts 'Customers: ' + Customer.count.to_s"
```

**Ejecutar:**
```bash
chmod +x scripts/reset_databases.sh
./scripts/reset_databases.sh
```

---

### Script: Verificar Estado de Bases de Datos

Crear archivo: `scripts/check_databases.sh`

```bash
#!/bin/bash

echo "Database Status Check"
echo "========================"
echo ""

echo "Order Service:"
echo "--------------"
docker compose exec order_service bundle exec rails runner "
  puts 'Total Orders: ' + Order.count.to_s
  puts 'Pending Orders: ' + Order.where(status: 'pending').count.to_s
  puts 'Latest Order: ' + (Order.last&.product_name || 'None')
"

echo ""
echo "Customer Service:"
echo "-----------------"
docker compose exec customer_service bundle exec rails runner "
  puts 'Total Customers: ' + Customer.count.to_s
  puts 'Customers with Orders: ' + Customer.where('orders_count > 0').count.to_s
  puts 'Total Processed Events: ' + ProcessedEvent.count.to_s
  puts 'Top Customer: ' + (Customer.order(orders_count: :desc).first&.customer_name || 'None')
"
```

**Ejecutar:**
```bash
chmod +x scripts/check_databases.sh
./scripts/check_databases.sh
```

---

### Script: Backup de Bases de Datos

Crear archivo: `scripts/backup_databases.sh`

```bash
#!/bin/bash

BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

echo "Backing up databases..."

# Backup Order Service
docker compose exec -T postgres_order pg_dump -U postgres order_service_development > \
  "$BACKUP_DIR/order_service_$TIMESTAMP.sql"
echo "Order Service backed up"

# Backup Customer Service
docker compose exec -T postgres_customer pg_dump -U postgres customer_service_development > \
  "$BACKUP_DIR/customer_service_$TIMESTAMP.sql"
echo "Customer Service backed up"

echo ""
echo "Backups saved to: $BACKUP_DIR"
ls -lh $BACKUP_DIR/*$TIMESTAMP.sql
```

**Ejecutar:**
```bash
chmod +x scripts/backup_databases.sh
./scripts/backup_databases.sh
```

---

### Script: Restaurar Backup

Crear archivo: `scripts/restore_databases.sh`

```bash
#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: ./restore_databases.sh <timestamp>"
  echo "Example: ./restore_databases.sh 20260308_192000"
  exit 1
fi

TIMESTAMP=$1
BACKUP_DIR="./backups"

echo "Restoring databases from backup: $TIMESTAMP"

# Restore Order Service
if [ -f "$BACKUP_DIR/order_service_$TIMESTAMP.sql" ]; then
  docker compose exec order_service bundle exec rails db:drop
  docker compose exec order_service bundle exec rails db:create
  cat "$BACKUP_DIR/order_service_$TIMESTAMP.sql" | \
    docker compose exec -T postgres_order psql -U postgres order_service_development
  echo "Order Service restored"
else
  echo "Order Service backup not found"
fi

# Restore Customer Service
if [ -f "$BACKUP_DIR/customer_service_$TIMESTAMP.sql" ]; then
  docker compose exec customer_service bundle exec rails db:drop
  docker compose exec customer_service bundle exec rails db:create
  cat "$BACKUP_DIR/customer_service_$TIMESTAMP.sql" | \
    docker compose exec -T postgres_customer psql -U postgres customer_service_development
  echo "Customer Service restored"
else
  echo "Customer Service backup not found"
fi

echo ""
echo "Restore complete!"
```

**Ejecutar:**
```bash
chmod +x scripts/restore_databases.sh
./scripts/restore_databases.sh 20260308_192000
```

---

## Comandos Comunes

### Crear Nueva Migración

```bash
# Order Service
docker compose exec order_service bundle exec rails generate migration AddColumnToOrders column_name:type

# Customer Service
docker compose exec customer_service bundle exec rails generate migration AddColumnToCustomers column_name:type
```

### Ejecutar Migraciones

```bash
# Ejecutar todas las migraciones pendientes
docker compose exec order_service bundle exec rails db:migrate
docker compose exec customer_service bundle exec rails db:migrate

# Ejecutar migración específica
docker compose exec order_service bundle exec rails db:migrate:up VERSION=20260308181906
```

### Revertir Migraciones

```bash
# Revertir última migración
docker compose exec order_service bundle exec rails db:rollback

# Revertir N migraciones
docker compose exec order_service bundle exec rails db:rollback STEP=2

# Revertir a versión específica
docker compose exec order_service bundle exec rails db:migrate:down VERSION=20260308181906
```

### Ver Estado de Migraciones

```bash
docker compose exec order_service bundle exec rails db:migrate:status
docker compose exec customer_service bundle exec rails db:migrate:status
```

### Ejecutar Seeds

```bash
# Ejecutar seeds
docker compose exec customer_service bundle exec rails db:seed

# Re-ejecutar seeds (drop, create, migrate, seed)
docker compose exec customer_service bundle exec rails db:reset
```

### Acceso Directo a PostgreSQL

```bash
# Order Service
docker compose exec postgres_order psql -U postgres -d order_service_development

# Customer Service
docker compose exec postgres_customer psql -U postgres -d customer_service_development
```

**Comandos útiles en psql:**
```sql
-- Ver todas las tablas
\dt

-- Describir estructura de tabla
\d orders
\d customers
\d processed_events

-- Ver datos
SELECT * FROM orders;
SELECT * FROM customers;
SELECT * FROM processed_events;

-- Salir
\q
```

---

## Verificación de Integridad

### Verificar Relaciones y Datos

```bash
# Verificar que todos los customer_id en orders existen en customer_service
docker compose exec order_service bundle exec rails runner "
  invalid_orders = Order.pluck(:customer_id).uniq
  puts 'Customer IDs in orders: ' + invalid_orders.inspect
"

# Verificar consistencia de orders_count
docker compose exec customer_service bundle exec rails runner "
  Customer.find_each do |customer|
    # Nota: Este conteo no será exacto porque las órdenes están en otro servicio
    puts \"Customer #{customer.id}: orders_count = #{customer.orders_count}\"
  end
"

# Verificar eventos procesados
docker compose exec customer_service bundle exec rails runner "
  puts 'Total events processed: ' + ProcessedEvent.count.to_s
  puts 'Latest event: ' + (ProcessedEvent.order(processed_at: :desc).first&.event_id || 'None')
"
```

---

## Notas Importantes

### Idempotencia en processed_events

La tabla `processed_events` es crítica para garantizar que los eventos de RabbitMQ se procesen exactamente una vez:

```ruby
# Patrón de uso en OrderCreatedConsumer
ActiveRecord::Base.transaction do
  ProcessedEvent.create!(event_id: event_id, processed_at: Time.current)
  customer.increment!(:orders_count)
end
```

Si el `event_id` ya existe, la transacción falla y el evento no se procesa nuevamente.

### Limpieza de processed_events

Para evitar que la tabla crezca indefinidamente, puedes crear una tarea de limpieza:

```ruby
# lib/tasks/cleanup.rake
namespace :cleanup do
  desc "Remove processed events older than 30 days"
  task old_events: :environment do
    deleted = ProcessedEvent.where('processed_at < ?', 30.days.ago).delete_all
    puts "Deleted #{deleted} old processed events"
  end
end
```

**Ejecutar:**
```bash
docker compose exec customer_service bundle exec rails cleanup:old_events
```

### Migración de Datos entre Ambientes

Para migrar datos de desarrollo a producción, usa los scripts de backup/restore o exporta/importa datos específicos:

```bash
# Exportar clientes
docker compose exec customer_service bundle exec rails runner "
  File.write('customers_export.json', Customer.all.to_json)
"

# Importar clientes
docker compose exec customer_service bundle exec rails runner "
  data = JSON.parse(File.read('customers_export.json'))
  data.each { |attrs| Customer.create!(attrs.except('id', 'created_at', 'updated_at')) }
"
```

---

## Troubleshooting

### Error: "PG::ConnectionBad"

```bash
# Verificar que PostgreSQL está corriendo
docker compose ps postgres_order postgres_customer

# Reiniciar PostgreSQL
docker compose restart postgres_order postgres_customer

# Verificar conexión
docker compose exec order_service bundle exec rails runner "puts ActiveRecord::Base.connection.active?"
```

### Error: "Migrations are pending"

```bash
# Ejecutar migraciones pendientes
docker compose exec order_service bundle exec rails db:migrate
docker compose exec customer_service bundle exec rails db:migrate
```

### Error: "Database does not exist"

```bash
# Crear base de datos
docker compose exec order_service bundle exec rails db:create
docker compose exec customer_service bundle exec rails db:create
```

### Resetear Todo desde Cero

```bash
# Detener servicios
docker compose down -v

# Levantar servicios
docker compose up -d

# Esperar a que PostgreSQL esté listo
sleep 10

# Crear y migrar bases de datos
docker compose exec order_service bundle exec rails db:create db:migrate
docker compose exec customer_service bundle exec rails db:create db:migrate db:seed

# Configurar RabbitMQ
docker compose exec customer_service bundle exec rake rabbitmq:setup
```
