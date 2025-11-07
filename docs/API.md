# API Documentation

## Base URL

Все API эндпоинты доступны по пути `/api`.

## Аутентификация

Запросы от агентов должны содержать заголовок `X-Node-Signature` с HMAC-подписью тела запроса, вычисленной с использованием `secret_key` ноды или `registration_secret` при первой регистрации.

Запросы от мастер-панели к агентам содержат заголовок `X-Master-Signature`.

## Эндпоинты

### Health Check

```
GET /api/health
```

Проверка доступности сервиса.

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2025-01-20T10:00:00Z"
}
```

### Регистрация ноды

```
POST /api/nodes/register
```

Регистрация новой ноды на мастер-панели.

**Headers:**
- `X-Node-Signature`: HMAC подпись тела запроса (используется `registration_secret`)

**Request Body:**
```json
{
  "id": "node-001",
  "name": "EU Node 01",
  "master_url": "https://master.example.com",
  "ip_address": "192.168.1.100",
  "hostname": "node01.example.com",
  "location": "EU",
  "xray_version": "latest",
  "listen_addr": ":8080"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "node_id": "node-001",
    "secret_key": "generated-secret-key",
    "status": "online"
  }
}
```

### Получение конфигурации ноды

```
GET /api/nodes/:node_id/config
```

Получение конфигурации Xray для ноды.

**Headers:**
- `X-Node-Signature`: HMAC подпись пути запроса

**Response:**
```json
{
  "success": true,
  "data": {
    "inbounds": [...],
    "outbounds": [...],
    "clients": [...],
    "routing": {...},
    "dns": {...},
    "policy": {...},
    "transport": {...},
    "log": {...},
    "last_updated_at": "2025-01-20T10:00:00Z"
  }
}
```

### Отправка статистики ноды

```
POST /api/nodes/:node_id/stats
```

Отправка телеметрии и статистики от ноды.

**Headers:**
- `X-Node-Signature`: HMAC подпись тела запроса

**Request Body:**
```json
{
  "status": "online",
  "cpu_usage": 45.2,
  "memory_usage": 67.8,
  "online_users": 150,
  "clients": [
    {
      "client_id": 1,
      "upload": 1024000,
      "download": 2048000,
      "last_used": "2025-01-20T10:00:00Z"
    }
  ]
}
```

**Response:**
```json
{
  "success": true
}
```

### Получение подписки

```
GET /api/subscriptions/:client_uuid?format=json|clash|v2ray|shadowrocket
```

Генерация мультиформатной подписки для клиента.

**Query Parameters:**
- `format`: формат подписки (`json`, `clash`, `v2ray`, `shadowrocket`), по умолчанию `json`

**Response:**
- Для `format=json`: JSON объект с конфигурацией
- Для `format=clash`: YAML конфигурация Clash
- Для `format=v2ray` или `format=shadowrocket`: текстовый список ссылок (по одной на строку)

### Административные эндпоинты

#### Dashboard метрики

```
GET /api/admin/dashboard
```

Получение агрегированных метрик для дашборда.

**Response:**
```json
{
  "success": true,
  "data": {
    "total_nodes": 10,
    "online_nodes": 8,
    "degraded_nodes": 1,
    "offline_nodes": 1,
    "online_users": 250,
    "traffic_24h_gb": 1250.5,
    "updated_at": "2025-01-20T10:00:00Z"
  }
}
```

#### Список нод

```
GET /api/admin/nodes
```

Получение списка всех нод с их группами и статусами.

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "node-001",
      "name": "EU Node 01",
      "status": "online",
      "ip_address": "192.168.1.100",
      "hostname": "node01.example.com",
      "location": "EU",
      "xray_version": "1.8.25",
      "listen_addr": ":8080",
      "last_seen": "2025-01-20T10:00:00Z",
      "groups": [
        {
          "id": 1,
          "name": "Premium EU"
        }
      ]
    }
  ]
}
```

## Коды ошибок

- `400 Bad Request` — неверный формат запроса
- `401 Unauthorized` — неверная или отсутствующая подпись
- `404 Not Found` — ресурс не найден
- `500 Internal Server Error` — внутренняя ошибка сервера

Все ошибки возвращаются в формате:
```json
{
  "success": false,
  "message": "описание ошибки"
}
```

