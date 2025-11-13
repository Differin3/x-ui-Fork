# Скрипт регистрации ноды

Скрипт `register_node.sh` автоматизирует процесс регистрации удаленной ноды 3x-ui в мастер-панели.

## Требования

- `bash` (версия 4.0+)
- `curl` (для HTTP запросов)
- `jq` (для обработки JSON)

### Установка зависимостей

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install curl jq
```

**CentOS/RHEL:**
```bash
sudo yum install curl jq
```

**macOS:**
```bash
brew install curl jq
```

## Использование

### Базовое использование

```bash
./scripts/register_node.sh \
  -m master.example.com \
  -n "Node 1" \
  -h node1.example.com \
  -w admin123
```

### С кастомными портами

```bash
./scripts/register_node.sh \
  -m master.example.com \
  -p 8080 \
  -n "Node 2" \
  -h node2.example.com \
  -o 2096 \
  -w admin123
```

### С явным External API Key

```bash
./scripts/register_node.sh \
  -m master.example.com \
  -n "Node 3" \
  -h node3.example.com \
  -w admin123 \
  -k "MY_EXTERNAL_API_KEY"
```

### С пропуском проверки SSL

```bash
./scripts/register_node.sh \
  -m master.example.com \
  -n "Node 4" \
  -h node4.example.com \
  -w admin123 \
  -s
```

## Параметры

| Параметр | Короткий | Описание | Обязательный | По умолчанию |
|----------|----------|----------|--------------|--------------|
| `--master-host` | `-m` | Хост мастер-панели | Да | - |
| `--master-port` | `-p` | Порт мастер-панели | Нет | 5050 |
| `--master-protocol` | `-P` | Протокол мастер-панели (http/https) | Нет | http |
| `--node-name` | `-n` | Имя ноды | Да | - |
| `--node-host` | `-h` | Хост удаленной ноды | Да | - |
| `--node-port` | `-o` | Порт удаленной ноды | Нет | 5050 |
| `--node-protocol` | `-O` | Протокол удаленной ноды (http/https) | Нет | https |
| `--username` | `-u` | Имя пользователя мастер-панели | Нет | admin |
| `--password` | `-w` | Пароль мастер-панели | Да | - |
| `--api-key` | `-k` | External API Key | Нет | - |
| `--skip-ssl-verify` | `-s` | Пропустить проверку SSL | Нет | false |
| `--help` | - | Показать справку | Нет | - |

## Процесс регистрации

1. **Проверка зависимостей** - скрипт проверяет наличие `curl` и `jq`
2. **Вход в мастер-панель** - автоматический вход с указанными учетными данными
3. **Получение External API Key** (опционально) - если ключ не указан, скрипт предупредит о необходимости установить его вручную
4. **Регистрация ноды** - отправка запроса на создание ноды через API

## Настройка External API Key

Если External API Key не указан при регистрации, его нужно установить вручную:

1. Войдите в мастер-панель
2. Перейдите в **Settings → Security**
3. Найдите поле **External API Key**
4. Нажмите **Generate** для создания нового ключа
5. Скопируйте ключ и установите его на удаленной ноде:
   - Войдите в панель удаленной ноды
   - Перейдите в **Settings → Security**
   - Вставьте ключ в поле **External API Key**
   - Нажмите **Update**

## Примеры использования

### Регистрация нескольких нод

```bash
#!/bin/bash

MASTER="master.example.com"
PASSWORD="admin123"

# Регистрация ноды 1
./scripts/register_node.sh \
  -m "$MASTER" \
  -n "US Node" \
  -h us-node.example.com \
  -w "$PASSWORD"

# Регистрация ноды 2
./scripts/register_node.sh \
  -m "$MASTER" \
  -n "EU Node" \
  -h eu-node.example.com \
  -w "$PASSWORD"

# Регистрация ноды 3
./scripts/register_node.sh \
  -m "$MASTER" \
  -n "Asia Node" \
  -h asia-node.example.com \
  -w "$PASSWORD"
```

## Устранение неполадок

### Ошибка: "Login failed"

- Проверьте правильность имени пользователя и пароля
- Убедитесь, что мастер-панель доступна по указанному адресу
- Проверьте, что порт указан правильно

### Ошибка: "Failed to register node"

- Убедитесь, что нода доступна по указанному адресу
- Проверьте, что External API Key установлен на удаленной ноде
- Убедитесь, что порт ноды указан правильно

### Ошибка: "Missing required dependencies"

Установите недостающие зависимости:
```bash
# Ubuntu/Debian
sudo apt-get install curl jq

# CentOS/RHEL
sudo yum install curl jq
```

## Безопасность

- **Не храните пароли в скриптах** - используйте переменные окружения или файлы с ограниченными правами доступа
- **Используйте HTTPS** - для продакшн окружений всегда используйте `--master-protocol https` и `--node-protocol https`