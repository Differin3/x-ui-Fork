# Решение проблем

## Ошибка: "Binary was compiled with 'CGO_ENABLED=0', go-sqlite3 requires cgo"

**Проблема:** Бинарник был скомпилирован без поддержки CGO, но SQLite драйвер требует CGO.

**Решение:**

1. Убедитесь, что установлен компилятор C:
   ```bash
   # Debian/Ubuntu
   apt-get install -y build-essential
   
   # CentOS/RHEL
   yum install -y gcc
   ```

2. Добавьте Go в PATH и пересоберите бинарник с CGO:
   ```bash
   export PATH=$PATH:/usr/local/go/bin
   cd /opt/vpn-master
   CGO_ENABLED=1 go build -o /usr/local/bin/vpn-master ./cmd/master
   systemctl restart vpn-master
   ```
   
   Или используйте полный путь к Go:
   ```bash
   cd /opt/vpn-master
   CGO_ENABLED=1 /usr/local/go/bin/go build -o /usr/local/bin/vpn-master ./cmd/master
   systemctl restart vpn-master
   ```

3. Или переустановите через обновлённый скрипт:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Differin3/x-ui-Fork/main/install.sh | sudo bash
   ```

Обновлённый скрипт автоматически:
- Проверяет наличие gcc/build-essential
- Устанавливает их при необходимости
- Собирает с `CGO_ENABLED=1`

## Другие проблемы

### Сервис не запускается

Проверьте логи:
```bash
journalctl -u vpn-master -n 50
```

### База данных не создаётся

Убедитесь, что директория существует и доступна для записи:
```bash
mkdir -p /var/lib/vpn-master
chmod 700 /var/lib/vpn-master
```

### Порт занят

Измените порт в `/etc/vpn-master.env`:
```bash
MASTER_HTTP_PORT=8086
systemctl restart vpn-master
```

