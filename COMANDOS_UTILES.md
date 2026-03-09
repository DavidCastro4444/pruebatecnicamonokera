# Comandos Útiles - Rails Microservices Monorepo

## Iniciar el Proyecto

### Levantar todos los servicios
```bash
docker compose up -d
```

### Levantar servicios con logs en tiempo real
```bash
docker compose up
```

### Reconstruir imágenes y levantar servicios
```bash
docker compose up -d --build
```

---

## Monitoreo y Estado

### Ver estado de todos los servicios
```bash
docker compose ps
```

### Ver logs de un servicio específico
```bash
# Order Service
docker compose logs -f order_service

# Customer Service
docker compose logs -f customer_service

# RabbitMQ
docker compose logs -f rabbitmq

# PostgreSQL Order
docker compose logs -f postgres_order

# PostgreSQL Customer
docker compose logs -f postgres_customer
```

### Ver últimas 50 líneas de logs
```bash
docker compose logs --tail=50 order_service
docker compose logs --tail=50 customer_service
```

---

## Gestión de Bases de Datos

### Crear bases de datos
```bash
docker compose exec order_service bundle exec rails db:create
docker compose exec customer_service bundle exec rails db:create
```

### Ejecutar migraciones
```bash
docker compose exec order_service bundle exec rails db:migrate
docker compose exec customer_service bundle exec rails db:migrate
```

### Cargar datos de prueba (seeds)
```bash
docker compose exec customer_service bundle exec rails db:seed
```

### Resetear base de datos (drop, create, migrate, seed)
```bash
docker compose exec order_service bundle exec rails db:reset
docker compose exec customer_service bundle exec rails db:reset
```

### Acceder a consola de Rails
```bash
docker compose exec order_service bundle exec rails console
docker compose exec customer_service bundle exec rails console
```

### Acceder a PostgreSQL directamente
```bash
# Order Service DB
docker compose exec postgres_order psql -U postgres -d order_service_development

# Customer Service DB
docker compose exec postgres_customer psql -U postgres -d customer_service_development
```

---

## RabbitMQ

### Configurar infraestructura de RabbitMQ
```bash
docker compose exec customer_service bundle exec rake rabbitmq:setup
```

### Iniciar consumer en background
```bash
docker compose exec -d customer_service bundle exec rake rabbitmq:consume
```

### Iniciar consumer en foreground (ver logs)
```bash
docker compose exec customer_service bundle exec rake rabbitmq:consume
```

### Acceder a RabbitMQ Management UI
```
URL: http://localhost:15672
Usuario: guest
Password: guest
```

---

## Testing

### Ejecutar todos los tests

#### Order Service
```bash
docker compose exec order_service bundle exec rspec
```

#### Customer Service
```bash
docker compose exec customer_service bundle exec rspec
```

### Ejecutar tests específicos
```bash
# Request specs
docker compose exec order_service bundle exec rspec spec/requests

# Service specs
docker compose exec order_service bundle exec rspec spec/services

# Consumer specs
docker compose exec customer_service bundle exec rspec spec/consumers

# Archivo específico
docker compose exec order_service bundle exec rspec spec/requests/orders_spec.rb

# Test específico por línea
docker compose exec order_service bundle exec rspec spec/requests/orders_spec.rb:45
```

### Ejecutar tests con formato detallado
```bash
docker compose exec order_service bundle exec rspec --format documentation
docker compose exec customer_service bundle exec rspec --format documentation
```

---

## Pruebas Manuales de API

### Health Checks
```powershell
# Order Service
Invoke-WebRequest -Uri http://localhost:3001/health -UseBasicParsing

# Customer Service
Invoke-WebRequest -Uri http://localhost:3002/health -UseBasicParsing
```

### Crear una Orden
```powershell
Invoke-WebRequest -Uri http://localhost:3001/orders `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"order":{"customer_id":1,"product_name":"Laptop Dell XPS 15","quantity":2,"price":1299.99}}'
```

### Listar Órdenes de un Cliente
```powershell
Invoke-WebRequest -Uri "http://localhost:3001/orders?customer_id=1" -UseBasicParsing
```

### Obtener Información de un Cliente
```powershell
Invoke-WebRequest -Uri http://localhost:3002/customers/1 -UseBasicParsing
```

### Ver Respuesta Formateada (JSON)
```powershell
(Invoke-WebRequest -Uri http://localhost:3002/customers/1 -UseBasicParsing).Content | ConvertFrom-Json | ConvertTo-Json
```

---

## Desarrollo

### Instalar una nueva gema

#### Order Service
```bash
docker compose exec order_service bundle add nombre_gema
docker compose restart order_service
```

#### Customer Service
```bash
docker compose exec customer_service bundle add nombre_gema
docker compose restart customer_service
```

### Crear una migración
```bash
# Order Service
docker compose exec order_service bundle exec rails generate migration NombreMigracion
docker compose exec order_service bundle exec rails db:migrate

# Customer Service
docker compose exec customer_service bundle exec rails generate migration NombreMigracion
docker compose exec customer_service bundle exec rails db:migrate
```

### Acceder al contenedor con bash
```bash
docker compose exec order_service bash
docker compose exec customer_service bash
```

### Ver variables de entorno
```bash
docker compose exec order_service env
docker compose exec customer_service env
```

---

## Limpieza

### Detener servicios
```bash
docker compose down
```

### Detener y eliminar volúmenes (reset completo)
```bash
docker compose down -v
```

### Eliminar imágenes también
```bash
docker compose down --rmi all
```

### Limpiar sistema Docker completo
```bash
docker system prune -f
```

### Limpiar todo (imágenes, contenedores, volúmenes, redes)
```bash
docker system prune -a --volumes -f
```

---

## Métricas y Monitoreo

### Contar registros en base de datos
```bash
# Órdenes creadas
docker compose exec order_service bundle exec rails runner "puts Order.count"

# Eventos procesados
docker compose exec customer_service bundle exec rails runner "puts ProcessedEvent.count"

# Clientes con órdenes
docker compose exec customer_service bundle exec rails runner "puts Customer.where('orders_count > 0').count"
```

### Ver uso de recursos
```bash
docker stats
```

### Ver espacio usado por Docker
```bash
docker system df
```

---

## Reiniciar Servicios

### Reiniciar un servicio específico
```bash
docker compose restart order_service
docker compose restart customer_service
```

### Reiniciar todos los servicios
```bash
docker compose restart
```

---

## Debugging

### Ver procesos dentro de un contenedor
```bash
docker compose exec order_service ps aux
```

### Verificar conectividad entre servicios
```bash
# Desde order_service a customer_service
docker compose exec order_service curl http://customer_service:3000/health

# Desde customer_service a rabbitmq
docker compose exec customer_service nc -zv rabbitmq 5672
```

### Ver configuración de Docker Compose
```bash
docker compose config
```

---

## Notas Importantes

- **Puertos Expuestos:**
  - Order Service: `3001`
  - Customer Service: `3002`
  - PostgreSQL Order: `5433`
  - PostgreSQL Customer: `5434`
  - RabbitMQ AMQP: `5672`
  - RabbitMQ Management: `15672`

- **Credenciales por Defecto:**
  - PostgreSQL: `postgres/postgres`
  - RabbitMQ: `guest/guest`

- **Datos de Prueba:**
  - El seed crea 5 clientes de prueba (IDs 1-5)
  - Usa `customer_id: 1` para pruebas manuales
