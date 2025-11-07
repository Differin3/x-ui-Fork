# Быстрый старт

## Первый вход

После установки создаётся администратор по умолчанию:
- **Username:** `admin`
- **Password:** `admin`

⚠️ **ВАЖНО:** Сразу после первого входа измените пароль!

## Проверка работы сервиса

После установки сервис должен быть запущен. Проверьте статус:

```bash
systemctl status vpn-master
```

## Создание нового администратора

Для создания нового администратора используйте скрипт:

```bash
chmod +x /opt/vpn-master/scripts/create-admin.sh
/opt/vpn-master/scripts/create-admin.sh
```

Или через API (требует авторизации):

```bash
curl -X POST http://localhost:8085/api/admin/users \
  -H "Cookie: auth_token=YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"newadmin","password":"securepassword"}'
```

## Тестирование API

### 1. Health Check

```bash
curl http://localhost:8085/api/health
```

Ожидаемый ответ:
```json
{
  "status": "ok",
  "timestamp": "2025-11-07T19:52:12Z"
}
```

### 2. Dashboard метрики

```bash
curl http://localhost:8085/api/admin/dashboard
```

### 3. Список нод

```bash
curl http://localhost:8085/api/admin/nodes
```

### 4. Поиск сертификатов

```bash
# Поиск по части домена
curl "http://localhost:8085/api/admin/certificates/search?q=example"

# Получение сертификата по домену
curl http://localhost:8085/api/admin/certificates/domain/example.com

# Проверка сертификата
curl -X POST http://localhost:8085/api/admin/certificates/check/example.com
```

## Добавление домена и сертификата

Для добавления домена и сертификата используйте API или добавьте напрямую в базу данных.

### Через SQLite

```bash
sqlite3 /var/lib/vpn-master/master.db
```

```sql
INSERT INTO domain_certificates (domain, cert_file, key_file, auto_renew, created_at, updated_at)
VALUES ('example.com', '/etc/ssl/certs/example.com/fullchain.pem', '/etc/ssl/certs/example.com/privkey.pem', 1, datetime('now'), datetime('now'));
```

## Веб-интерфейс

Веб-интерфейс находится в `web/admin/` и требует сборки. Для разработки:

```bash
cd web/admin
npm install
npm run dev
```

Для production сборки:

```bash
cd web/admin
npm install
npm run build
```

Собранные файлы будут в `web/admin/dist/`. Их можно обслуживать через nginx или интегрировать в мастер-панель.

## Проблемы?

См. [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

