# План реализации мультинодового управления для 3x-ui

## Обзор проекта

Данный план описывает реализацию функций:
1. **Управление несколькими нодами** - централизованное управление несколькими серверами 3x-ui
2. **Мультиподписка** - объединение нескольких нод в одну подписку
3. **Общий дашборд** - агрегированная статистика со всех нод
4. **Карта мира** - визуализация расположения серверов на реальной карте мира

## Архитектура

### Текущая архитектура
- **Backend**: Go (Gin framework)
- **База данных**: SQLite (GORM)
- **Frontend**: Vue.js + Ant Design Vue
- **Xray**: Управление через API и конфигурационные файлы

### Новая архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                    Главная нода (Master)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Database   │  │   API Server │  │  Web UI      │      │
│  │  (SQLite)    │  │   (Gin)      │  │  (Vue.js)    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │              │
│         └──────────────────┼──────────────────┘              │
│                            │                                 │
│         ┌──────────────────┴──────────────────┐             │
│         │     Node Management Service          │             │
│         │  - NodeClient (HTTP API)             │             │
│         │  - NodeSync (синхронизация)          │             │
│         └──────────────────┬──────────────────┘             │
└────────────────────────────┼─────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼────────┐  ┌────────▼────────┐  ┌───────▼────────┐
│   Node 1       │  │   Node 2        │  │   Node N       │
│  (Slave)       │  │   (Slave)       │  │   (Slave)      │
│                │  │                 │  │                │
│  ┌──────────┐  │  │  ┌──────────┐  │  │  ┌──────────┐  │
│  │ 3x-ui    │  │  │  │ 3x-ui    │  │  │  │ 3x-ui    │  │
│  │ API      │  │  │  │ API      │  │  │  │ API      │  │
│  └──────────┘  │  │  └──────────┘  │  │  └──────────┘  │
└────────────────┘  └────────────────┘  └────────────────┘
```

## Фаза 1: База данных и модели

### 1.1 Модель Node (Нода/Сервер)

```go
type Node struct {
    Id          int    `json:"id" gorm:"primaryKey;autoIncrement"`
    Name        string `json:"name" form:"name"`                    // Название ноды
    Host        string `json:"host" form:"host"`                    // IP или домен
    Port        int    `json:"port" form:"port"`                    // Порт API
    ApiKey      string `json:"apiKey" form:"apiKey"`                // API ключ для аутентификации
    Protocol    string `json:"protocol" form:"protocol"`            // http или https
    Location    string `json:"location" form:"location"`            // Название локации (например, "Moscow")
    Country     string `json:"country" form:"country"`              // Код страны (ISO 3166-1 alpha-2)
    City        string `json:"city" form:"city"`                    // Город
    Latitude    float64 `json:"latitude" form:"latitude"`           // Широта
    Longitude   float64 `json:"longitude" form:"longitude"`         // Долгота
    Enable      bool   `json:"enable" form:"enable"`                // Включена ли нода
    Status      string `json:"status" form:"status"`                // online, offline, error
    LastCheck   int64  `json:"lastCheck" form:"lastCheck"`          // Время последней проверки
    Remark      string `json:"remark" form:"remark"`                // Примечание
    CreatedAt   int64  `json:"createdAt" form:"createdAt"`          // Время создания
    UpdatedAt   int64  `json:"updatedAt" form:"updatedAt"`          // Время обновления
}
```

### 1.2 Модель MultiSubscription (Мультиподписка)

```go
type MultiSubscription struct {
    Id          int    `json:"id" gorm:"primaryKey;autoIncrement"`
    Name        string `json:"name" form:"name"`                    // Название подписки
    SubId       string `json:"subId" form:"subId" gorm:"unique"`    // Уникальный ID подписки
    NodeIds     string `json:"nodeIds" form:"nodeIds"`              // JSON массив ID нод
    Enable      bool   `json:"enable" form:"enable"`                // Включена ли подписка
    Remark      string `json:"remark" form:"remark"`                // Примечание
    CreatedAt   int64  `json:"createdAt" form:"createdAt"`          // Время создания
    UpdatedAt   int64  `json:"updatedAt" form:"updatedAt"`          // Время обновления
}
```

### 1.3 Модель NodeStats (Статистика ноды)

```go
type NodeStats struct {
    Id          int    `json:"id" gorm:"primaryKey;autoIncrement"`
    NodeId      int    `json:"nodeId" form:"nodeId"`                // ID ноды
    Cpu         float64 `json:"cpu" form:"cpu"`                     // CPU использование
    Mem         uint64  `json:"mem" form:"mem"`                     // Использование памяти
    Disk        uint64  `json:"disk" form:"disk"`                   // Использование диска
    NetUp       uint64  `json:"netUp" form:"netUp"`                 // Сетевой трафик UP
    NetDown     uint64  `json:"netDown" form:"netDown"`             // Сетевой трафик DOWN
    Uptime      uint64  `json:"uptime" form:"uptime"`               // Время работы
    XrayStatus  string  `json:"xrayStatus" form:"xrayStatus"`       // Статус Xray
    Clients     int     `json:"clients" form:"clients"`             // Количество клиентов
    Inbounds    int     `json:"inbounds" form:"inbounds"`           // Количество inbounds
    CollectedAt int64   `json:"collectedAt" form:"collectedAt"`     // Время сбора статистики
}
```

### 1.4 Миграция базы данных

Добавить в `database/db.go`:
- Автомиграцию новых моделей
- Индексы для оптимизации запросов

## Фаза 2: Backend - Управление нодами

### 2.1 NodeService

Создать `web/service/node.go`:
- `AddNode(node *model.Node) error` - добавление ноды
- `UpdateNode(node *model.Node) error` - обновление ноды
- `DeleteNode(id int) error` - удаление ноды
- `GetNode(id int) (*model.Node, error)` - получение ноды
- `GetAllNodes() ([]*model.Node, error)` - получение всех нод
- `CheckNodeStatus(node *model.Node) (string, error)` - проверка статуса ноды
- `SyncNodeStats(nodeId int) error` - синхронизация статистики

### 2.2 NodeClient

Создать `web/service/node_client.go`:
- Клиент для связи с удаленными нодами через HTTP API
- Аутентификация через API ключ
- Методы:
  - `GetStatus() (*service.Status, error)` - получение статуса
  - `GetInbounds() ([]*model.Inbound, error)` - получение inbounds
  - `GetClients(subId string) ([]*model.Client, error)` - получение клиентов по subId
  - `SyncInbound(inbound *model.Inbound) error` - синхронизация inbound

### 2.3 NodeController

Создать `web/controller/node.go`:
- `GET /panel/api/nodes` - список всех нод
- `GET /panel/api/nodes/:id` - получение ноды
- `POST /panel/api/nodes` - создание ноды
- `PUT /panel/api/nodes/:id` - обновление ноды
- `DELETE /panel/api/nodes/:id` - удаление ноды
- `POST /panel/api/nodes/:id/check` - проверка статуса ноды
- `POST /panel/api/nodes/:id/sync` - синхронизация ноды
- `GET /panel/api/nodes/:id/stats` - статистика ноды

### 2.4 API для удаленных нод

Расширить API для поддержки внешнего доступа:
- Добавить middleware для аутентификации по API ключу
- Создать отдельные endpoints для внешнего API:
  - `GET /api/external/status` - статус ноды
  - `GET /api/external/inbounds` - список inbounds
  - `GET /api/external/clients?subId=xxx` - клиенты по subId
  - `GET /api/external/subscription/:subId` - подписка

## Фаза 3: Backend - Мультиподписка

### 3.1 MultiSubscriptionService

Создать `web/service/multi_subscription.go`:
- `CreateMultiSubscription(ms *model.MultiSubscription) error` - создание
- `UpdateMultiSubscription(ms *model.MultiSubscription) error` - обновление
- `DeleteMultiSubscription(id int) error` - удаление
- `GetMultiSubscription(id int) (*model.MultiSubscription, error)` - получение
- `GetAllMultiSubscriptions() ([]*model.MultiSubscription, error)` - получение всех
- `GenerateMultiSubscriptionLink(subId string, host string) (string, error)` - генерация ссылки

### 3.2 Расширение SubService

Модифицировать `sub/subService.go`:
- Добавить поддержку мультиподписки в `GetSubs()`
- Агрегировать данные с нескольких нод
- Объединять ссылки от разных нод в одну подписку

### 3.3 MultiSubscriptionController

Создать `web/controller/multi_subscription.go`:
- `GET /panel/api/multi-subscriptions` - список подписок
- `GET /panel/api/multi-subscriptions/:id` - получение подписки
- `POST /panel/api/multi-subscriptions` - создание подписки
- `PUT /panel/api/multi-subscriptions/:id` - обновление подписки
- `DELETE /panel/api/multi-subscriptions/:id` - удаление подписки

## Фаза 4: Backend - Дашборд

### 4.1 DashboardService

Создать `web/service/dashboard.go`:
- `GetAggregatedStats() (*AggregatedStats, error)` - агрегированная статистика
- `GetNodeStats(nodeId int) (*NodeStats, error)` - статистика ноды
- `GetAllNodesStats() ([]*NodeStats, error)` - статистика всех нод
- `GetDashboardData() (*DashboardData, error)` - данные для дашборда

### 4.2 DashboardController

Создать `web/controller/dashboard.go`:
- `GET /panel/api/dashboard/stats` - агрегированная статистика
- `GET /panel/api/dashboard/nodes` - статистика всех нод
- `GET /panel/api/dashboard/map` - данные для карты (ноды с координатами)

## Фаза 5: Frontend - Управление нодами

### 5.1 Страница управления нодами

Создать `web/html/nodes.html`:
- Таблица со списком нод
- Форма добавления/редактирования ноды
- Кнопки: проверка статуса, синхронизация, удаление
- Фильтры и поиск

### 5.2 Компоненты

- `web/html/form/node.html` - форма ноды
- `web/html/modals/node_modal.html` - модальное окно ноды
- `web/assets/js/model/node.js` - модель ноды для Vue.js

## Фаза 6: Frontend - Карта мира

### 6.1 Интеграция Leaflet

Добавить Leaflet.js в `web/assets`:
- `leaflet.css` - стили карты
- `leaflet.js` - библиотека карты

### 6.2 Страница карты

Создать `web/html/map.html`:
- Карта мира с маркерами нод
- Попапы с информацией о ноде
- Фильтры по странам/регионам
- Легенда со статусами нод

### 6.3 Компоненты

- `web/assets/js/map.js` - логика карты
- Интеграция с API для получения координат нод

## Фаза 7: Frontend - Мультиподписка

### 7.1 Страница мультиподписки

Создать `web/html/multi-subscriptions.html`:
- Таблица мультиподписок
- Форма создания/редактирования
- Выбор нод для включения в подписку
- Генерация ссылок подписки

### 7.2 Компоненты

- `web/html/form/multi_subscription.html` - форма мультиподписки
- `web/assets/js/model/multi_subscription.js` - модель мультиподписки

## Фаза 8: Frontend - Дашборд

### 8.1 Обновление главной страницы

Модифицировать `web/html/index.html`:
- Добавить секцию с нодами
- Агрегированная статистика
- Графики по нодам
- Ссылка на карту мира

### 8.2 Компоненты

- Виджеты для отображения статистики нод
- Графики использования ресурсов
- Таблица статусов нод

## Фаза 9: Синхронизация и фоновые задачи

### 9.1 Job для синхронизации

Создать `web/job/node_sync_job.go`:
- Периодическая проверка статуса нод
- Синхронизация статистики
- Обновление данных нод

### 9.2 Job для сбора статистики

Создать `web/job/node_stats_job.go`:
- Сбор статистики с нод
- Сохранение в базу данных
- Агрегация данных

## Фаза 10: Безопасность

### 10.1 API аутентификация

- Реализовать API ключи для нод
- Middleware для проверки API ключей
- Шифрование соединений (HTTPS)

### 10.2 Валидация данных

- Валидация входных данных
- Проверка координат
- Санитизация строк

## Фаза 11: Тестирование

### 11.1 Unit тесты

- Тесты для NodeService
- Тесты для NodeClient
- Тесты для MultiSubscriptionService

### 11.2 Integration тесты

- Тесты API endpoints
- Тесты синхронизации нод
- Тесты мультиподписки

## Фаза 12: Документация

### 12.1 API документация

- Документация API для нод
- Документация мультиподписки
- Примеры использования

### 12.2 Пользовательская документация

- Руководство по настройке нод
- Руководство по мультиподписке
- Руководство по использованию карты

## Порядок реализации

1. **Фаза 1** - База данных и модели (1-2 дня)
2. **Фаза 2** - Backend управление нодами (2-3 дня)
3. **Фаза 3** - Backend мультиподписка (2-3 дня)
4. **Фаза 4** - Backend дашборд (1-2 дня)
5. **Фаза 5** - Frontend управление нодами (2-3 дня)
6. **Фаза 6** - Frontend карта мира (2-3 дня)
7. **Фаза 7** - Frontend мультиподписка (1-2 дня)
8. **Фаза 8** - Frontend дашборд (1-2 дня)
9. **Фаза 9** - Синхронизация (1-2 дня)
10. **Фаза 10** - Безопасность (1 день)
11. **Фаза 11** - Тестирование (2-3 дня)
12. **Фаза 12** - Документация (1-2 дня)

**Общее время**: ~20-30 дней

## Технические детали

### API формат для нод

```json
{
  "name": "Moscow Node",
  "host": "192.168.1.100",
  "port": 5050,
  "apiKey": "your-api-key",
  "protocol": "https",
  "location": "Moscow",
  "country": "RU",
  "city": "Moscow",
  "latitude": 55.7558,
  "longitude": 37.6173,
  "enable": true,
  "remark": "Main server"
}
```

### Формат мультиподписки

```json
{
  "name": "Global Subscription",
  "subId": "multi-001",
  "nodeIds": [1, 2, 3],
  "enable": true,
  "remark": "All nodes"
}
```

### Геолокация нод

- ✅ Использовать сервисы для определения координат по IP (ip-api.com, ipapi.co, geojs.io с fallback)
- ✅ Ручной ввод координат
- ✅ Автоматическое определение по IP адресу (реализовано через GeolocationService)
- ✅ UI кнопка для автоопределения местоположения

## Зависимости

### Backend
- Существующие зависимости (Gin, GORM, etc.)
- HTTP клиент для связи с нодами
- Геокодинг библиотека (опционально)

### Frontend
- Leaflet.js для карты
- Существующие зависимости (Vue.js, Ant Design Vue)

## Известные ограничения

1. Синхронизация данных между нодами происходит в реальном времени через API
2. Для работы мультиподписки все ноды должны быть доступны
3. Координаты нод нужно указывать вручную или использовать сервис геолокации
4. API ключи хранятся в открытом виде в базе данных (можно зашифровать)

## Будущие улучшения

1. Автоматическая синхронизация конфигураций между нодами
2. Балансировка нагрузки между нодами
3. ✅ Автоматическое определение координат по IP (выполнено)
4. Графики использования ресурсов по нодам
5. Уведомления о проблемах с нодами
6. Резервное копирование конфигураций нод
7. Клонирование конфигураций между нодами

