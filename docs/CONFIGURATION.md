# Конфигурация

## Мастер-панель

### Переменные окружения

Создайте файл `/etc/vpn-master.env` или экспортируйте переменные:

```bash
# Порт HTTP API
MASTER_HTTP_PORT=8085

# Драйвер БД (sqlite, mysql, postgres)
MASTER_DB_DRIVER=sqlite

# DSN для подключения к БД
# SQLite: путь к файлу
MASTER_DB_DSN=/var/lib/vpn-master/master.db
# MySQL: user:password@tcp(host:port)/dbname?charset=utf8mb4&parseTime=True&loc=Local
# PostgreSQL: host=localhost user=user password=pass dbname=dbname port=5432 sslmode=disable

# Автоматические миграции БД
MASTER_DB_AUTO_MIGRATE=true

# HMAC секрет для подписи запросов (обязателен)
MASTER_HMAC_SECRET=your-secret-key-here

# TLS сертификаты (опционально)
MASTER_TLS_CERT_FILE=/path/to/cert.pem
MASTER_TLS_KEY_FILE=/path/to/key.pem
```

### Пример systemd service

```ini
[Unit]
Description=VPN Master Control Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/vpn-master.env
ExecStart=/usr/local/bin/vpn-master
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

## Node Agent

### Конфигурационный файл

Создайте `/etc/node-agent/config.json`:

```json
{
  "master_url": "https://master.example.com",
  "node_id": "node-001",
  "node_name": "EU Node 01",
  "registration_secret": "initial-secret-from-master",
  "secret_key": "",
  "xray_version": "latest",
  "install_path": "/usr/local/bin",
  "listen_addr": ":8080",
  "log_level": "info"
}
```

**Параметры:**
- `master_url` — URL мастер-панели (обязателен)
- `node_id` — уникальный идентификатор ноды (обязателен)
- `node_name` — человекочитаемое имя ноды (обязателен)
- `registration_secret` — секрет для первой регистрации (обязателен при первом запуске)
- `secret_key` — постоянный секрет, выдаётся мастером после регистрации (заполняется автоматически)
- `xray_version` — версия Xray-core для установки (`latest` или конкретная версия, например `v1.8.25`)
- `install_path` — путь для установки бинарника Xray (по умолчанию `/usr/local/bin`)
- `listen_addr` — адрес для прослушивания API агента (по умолчанию `:8080`)
- `log_level` — уровень логирования (`debug`, `info`, `warn`, `error`)

### Пример systemd service

```ini
[Unit]
Description=VPN Node Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/node-agent -config /etc/node-agent/config.json
Restart=always
RestartSec=5
Environment=GIN_MODE=release

[Install]
WantedBy=multi-user.target
```

## База данных

### SQLite (по умолчанию)

Файл БД создаётся автоматически при первом запуске. Убедитесь, что директория существует и доступна для записи:

```bash
mkdir -p /var/lib/vpn-master
chmod 700 /var/lib/vpn-master
```

### MySQL

```sql
CREATE DATABASE vpn_master CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'vpn_master'@'localhost' IDENTIFIED BY 'secure-password';
GRANT ALL PRIVILEGES ON vpn_master.* TO 'vpn_master'@'localhost';
FLUSH PRIVILEGES;
```

DSN: `vpn_master:secure-password@tcp(localhost:3306)/vpn_master?charset=utf8mb4&parseTime=True&loc=Local`

### PostgreSQL

```sql
CREATE DATABASE vpn_master;
CREATE USER vpn_master WITH PASSWORD 'secure-password';
GRANT ALL PRIVILEGES ON DATABASE vpn_master TO vpn_master;
```

DSN: `host=localhost user=vpn_master password=secure-password dbname=vpn_master port=5432 sslmode=disable`

## Безопасность

1. **HMAC секреты**: генерируйте криптографически стойкие секреты:
   ```bash
   openssl rand -hex 32
   ```

2. **TLS**: рекомендуется использовать TLS для мастер-панели в продакшене. Используйте Let's Encrypt или собственные сертификаты.

3. **Файрвол**: ограничьте доступ к портам:
   - Мастер-панель: только необходимые IP-адреса
   - Агенты: только мастер-панель может обращаться к `:8080`

4. **Права доступа**: конфигурационные файлы должны быть доступны только root:
   ```bash
   chmod 600 /etc/vpn-master.env
   chmod 600 /etc/node-agent/config.json
   ```

