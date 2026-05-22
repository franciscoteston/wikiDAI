#!/usr/bin/env sh
set -eu

export DB_HOST="127.0.0.1"
export DB_PORT="3306"
MYSQL_SOCKET="/run/mysqld/mysqld.sock"
export DB_DATABASE="${DB_DATABASE:-bookstack}"
export DB_USERNAME="${DB_USERNAME:-bookstack}"
export DB_PASSWORD="${DB_PASSWORD:-bookstack}"
export DB_SOCKET=""
export DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-rootbookstack}"

export APP_URL="${APP_URL:-https://franciscoteston-wikidai.hf.space}"
export APP_KEY="${APP_KEY:-}"
export BOOKSTACK_ADMIN_NAME="${BOOKSTACK_ADMIN_NAME:-Admin Demo}"
export BOOKSTACK_ADMIN_EMAIL="${BOOKSTACK_ADMIN_EMAIL:-admin@example.local}"
export BOOKSTACK_ADMIN_PASSWORD="${BOOKSTACK_ADMIN_PASSWORD:-change-me-now}"

# Persistência preferencial em /data quando disponível
if [ -d "/data" ]; then
  mkdir -p /data/mariadb /data/bookstack_uploads
  chown -R abc:abc /data/mariadb /data/bookstack_uploads
fi

# Configuração MariaDB
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

if [ -d "/data/mariadb" ]; then
  DB_DIR="/data/mariadb"
else
  DB_DIR="/config/mariadb"
  mkdir -p "$DB_DIR"
fi
chown -R mysql:mysql "$DB_DIR"

if [ ! -d "$DB_DIR/mysql" ]; then
  mariadb-install-db --user=mysql --datadir="$DB_DIR" >/dev/null
fi

mariadbd \
  --user=mysql \
  --datadir="$DB_DIR" \
  --socket="$MYSQL_SOCKET" \
  --skip-networking=0 \
  --bind-address=127.0.0.1 \
  --port=3306 &
MYSQL_PID=$!

# Espera banco
echo "Aguardando MariaDB via socket..."
MYSQL_READY=0
for i in $(seq 1 60); do
  if mariadb-admin ping --protocol=socket -S "$MYSQL_SOCKET" -uroot >/dev/null 2>&1; then
    MYSQL_READY=1
    break
  fi
  sleep 1
done

if [ "$MYSQL_READY" -ne 1 ]; then
  echo "MariaDB não ficou disponível via socket em tempo hábil."
  exit 1
fi
echo "MariaDB disponível."
echo "Criando banco e usuário..."
mariadb --protocol=socket -S "$MYSQL_SOCKET" -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${DB_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USERNAME}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USERNAME}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'%';
FLUSH PRIVILEGES;
SQL

# Configuração BookStack
echo "Preparando diretórios Laravel..."
ensure_dir() {
  path="$1"

  if [ -L "$path" ]; then
    target=$(readlink "$path")
    case "$target" in
      /*) ;;
      *) target="$(dirname "$path")/$target" ;;
    esac
    ensure_dir "$target"
    return
  fi

  if [ -d "$path" ]; then
    return
  fi

  if [ -e "$path" ]; then
    rm -f "$path"
  fi

  mkdir -p "$path"
}

ensure_dir /app/www/storage
ensure_dir /app/www/storage/logs
ensure_dir /app/www/storage/framework
ensure_dir /app/www/storage/framework/cache
ensure_dir /app/www/storage/framework/cache/data
ensure_dir /app/www/storage/framework/sessions
ensure_dir /app/www/storage/framework/views
ensure_dir /app/www/bootstrap
ensure_dir /app/www/bootstrap/cache

touch /app/www/storage/logs/laravel.log
chown abc:abc /app/www/storage/logs/laravel.log || true
chmod ug+rw /app/www/storage/logs/laravel.log || true

chown -R abc:abc /app/www/storage /app/www/bootstrap/cache || true
chmod -R ug+rwX /app/www/storage /app/www/bootstrap/cache || true


echo "Configurando .env do BookStack..."
if [ -f /app/www/.env.example ] && [ ! -f /config/www/.env ]; then
  cp /app/www/.env.example /config/www/.env
fi
if [ ! -e /app/www/.env ]; then
  ln -s /config/www/.env /app/www/.env
fi

upsert_env_var() {
  key="$1"
  value="$2"
  env_file="$3"
  escaped_value=$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s/^${key}=.*/${key}=${escaped_value}/" "$env_file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$env_file"
  fi
}

upsert_env_var "APP_URL" "${APP_URL}" "/config/www/.env"
upsert_env_var "DB_HOST" "127.0.0.1" "/config/www/.env"
upsert_env_var "DB_PORT" "3306" "/config/www/.env"
upsert_env_var "DB_DATABASE" "${DB_DATABASE}" "/config/www/.env"
upsert_env_var "DB_USERNAME" "${DB_USERNAME}" "/config/www/.env"
upsert_env_var "DB_PASSWORD" "${DB_PASSWORD}" "/config/www/.env"
upsert_env_var "DB_SOCKET" "" "/config/www/.env"
upsert_env_var "LOG_CHANNEL" "stderr" "/config/www/.env"

echo "Gerando APP_KEY..."
php /app/www/artisan key:generate --force
echo "Executando migrações BookStack..."
php /app/www/artisan migrate --force

# Admin demo
php /app/www/artisan bookstack:create-admin \
  --name "${BOOKSTACK_ADMIN_NAME}" \
  --email "${BOOKSTACK_ADMIN_EMAIL}" \
  --password "${BOOKSTACK_ADMIN_PASSWORD}" || true

# API token do admin para seed
API_CREDS=$(php /app/www/artisan bookstack:api-token:create "${BOOKSTACK_ADMIN_EMAIL}" seed-token 2>/dev/null || true)
API_ID=$(printf '%s' "$API_CREDS" | sed -n 's/.*Token ID:[[:space:]]*//p' | head -n1)
API_SECRET=$(printf '%s' "$API_CREDS" | sed -n 's/.*Token Secret:[[:space:]]*//p' | head -n1)

if [ -n "$API_ID" ] && [ -n "$API_SECRET" ]; then
  export BOOKSTACK_API_TOKEN_ID="$API_ID"
  export BOOKSTACK_API_TOKEN_SECRET="$API_SECRET"
  python3 /config/www/scripts/seed_bookstack.py /config/www/seed/manual_banco_mercado.json || true
fi

echo "Iniciando proxy local 7860 -> 80..."
socat TCP-LISTEN:7860,fork,reuseaddr TCP:127.0.0.1:80 &
PROXY_PID=$!

# Inicia web server BookStack (container base usa s6/nginx/php-fpm)
exec /init

# Em caso de término do init, garante encerramento do mysql
kill "$MYSQL_PID" >/dev/null 2>&1 || true
