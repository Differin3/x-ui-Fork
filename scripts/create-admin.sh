#!/bin/bash

# Скрипт для создания администратора VPN Master Panel

set -e

ENV_FILE="/etc/vpn-master.env"
DB_PATH="/var/lib/vpn-master/master.db"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Config file not found: $ENV_FILE"
    echo "Please install VPN Master Panel first."
    exit 1
fi

source "$ENV_FILE"

if [ -z "$MASTER_DB_DSN" ]; then
    DB_PATH="/var/lib/vpn-master/master.db"
else
    DB_PATH="$MASTER_DB_DSN"
fi

if [ ! -f "$DB_PATH" ]; then
    echo "Error: Database not found: $DB_PATH"
    echo "Please start VPN Master Panel service first to create database."
    exit 1
fi

read -p "Enter username: " USERNAME
if [ -z "$USERNAME" ]; then
    echo "Error: Username cannot be empty"
    exit 1
fi

read -sp "Enter password: " PASSWORD
echo
if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty"
    exit 1
fi

read -sp "Confirm password: " PASSWORD_CONFIRM
echo
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Error: Passwords do not match"
    exit 1
fi

# Проверяем наличие sqlite3
if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 not found. Installing..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y sqlite3
    elif command -v yum &> /dev/null; then
        yum install -y sqlite
    else
        echo "Error: Cannot install sqlite3. Please install it manually."
        exit 1
    fi
fi

# Генерируем хеш пароля используя Python или Go
if command -v python3 &> /dev/null; then
    HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$PASSWORD'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))")
elif command -v go &> /dev/null; then
    # Используем временный Go скрипт
    cat > /tmp/hash_password.go << 'EOF'
package main
import (
    "fmt"
    "os"
    "golang.org/x/crypto/bcrypt"
)
func main() {
    hash, _ := bcrypt.GenerateFromPassword([]byte(os.Args[1]), bcrypt.DefaultCost)
    fmt.Print(string(hash))
}
EOF
    export PATH=$PATH:/usr/local/go/bin
    HASH=$(go run /tmp/hash_password.go "$PASSWORD")
    rm /tmp/hash_password.go
else
    echo "Error: Need Python3 or Go to hash password"
    echo "Please install Python3 with bcrypt: pip3 install bcrypt"
    exit 1
fi

# Вставляем пользователя в базу
sqlite3 "$DB_PATH" << EOF
INSERT INTO admin_users (username, password_hash, is_active, created_at, updated_at)
VALUES ('$USERNAME', '$HASH', 1, datetime('now'), datetime('now'));
EOF

if [ $? -eq 0 ]; then
    echo "✓ Admin user '$USERNAME' created successfully!"
else
    echo "Error: Failed to create admin user"
    exit 1
fi

