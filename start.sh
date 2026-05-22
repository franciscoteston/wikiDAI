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
export BOOKSTACK_ADMIN_EMAIL="${BOOKSTACK_ADMIN_EMAIL:-admin@example.com}"
export BOOKSTACK_ADMIN_PASSWORD="${BOOKSTACK_ADMIN_PASSWORD:-change-me-now}"

if [ -z "${APP_KEY:-}" ]; then
  echo "ERRO: APP_KEY não definida. Configure APP_KEY como Secret no Hugging Face Space."
  exit 1
fi

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

# Preparação de diretórios persistentes em /config
mkdir -p \
  /config/www/uploads \
  /config/www/files \
  /config/www/images \
  /config/www/themes \
  /config/www/framework/cache \
  /config/www/framework/sessions \
  /config/www/framework/views \
  /config/www/framework/purifier \
  /config/backups \
  /config/log/bookstack

touch /config/log/bookstack/laravel.log
chown -R abc:abc /config/www /config/backups /config/log/bookstack || true
chmod -R ug+rwX /config/www /config/backups /config/log/bookstack || true

# Configuração BookStack
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
upsert_env_var "APP_KEY" "${APP_KEY}" "/config/www/.env"
upsert_env_var "DB_HOST" "127.0.0.1" "/config/www/.env"
upsert_env_var "DB_PORT" "3306" "/config/www/.env"
upsert_env_var "DB_DATABASE" "${DB_DATABASE}" "/config/www/.env"
upsert_env_var "DB_USERNAME" "${DB_USERNAME}" "/config/www/.env"
upsert_env_var "DB_PASSWORD" "${DB_PASSWORD}" "/config/www/.env"
upsert_env_var "DB_SOCKET" "" "/config/www/.env"
upsert_env_var "LOG_CHANNEL" "stderr" "/config/www/.env"

echo "Iniciando proxy local 7860 -> 80..."
socat TCP-LISTEN:7860,fork,reuseaddr TCP:127.0.0.1:80 &

RUN_AUX_PROCESS=1
if ! printf '%s' "$BOOKSTACK_ADMIN_EMAIL" | grep -q '@'; then
  echo "ERRO: BOOKSTACK_ADMIN_EMAIL inválido. O valor deve conter '@'."
  RUN_AUX_PROCESS=0
fi

if [ "$(printf '%s' "$BOOKSTACK_ADMIN_PASSWORD" | wc -c)" -lt 8 ]; then
  echo "ERRO: BOOKSTACK_ADMIN_PASSWORD inválido. A senha deve ter no mínimo 8 caracteres."
  RUN_AUX_PROCESS=0
fi

(
  if [ "$RUN_AUX_PROCESS" -ne 1 ]; then
    echo "Processo auxiliar desativado por configuração inválida de admin."
    exit 0
  fi

  echo "Processo auxiliar: aguardando BookStack responder..."
  for i in $(seq 1 300); do
    if command -v curl >/dev/null 2>&1; then
      if curl -fsS "http://127.0.0.1/api/docs" >/dev/null 2>&1 || curl -fsS "http://127.0.0.1" >/dev/null 2>&1; then
        break
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -O - "http://127.0.0.1/api/docs" >/dev/null 2>&1 || wget -q -O - "http://127.0.0.1" >/dev/null 2>&1; then
        break
      fi
    else
      if python3 - <<'PY' >/dev/null 2>&1
import urllib.request
for url in ("http://127.0.0.1/api/docs", "http://127.0.0.1"):
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            if r.status < 500:
                raise SystemExit(0)
    except Exception:
        pass
raise SystemExit(1)
PY
      then
        break
      fi
    fi
    sleep 1
  done

  php /app/www/artisan bookstack:create-admin \
    --name "${BOOKSTACK_ADMIN_NAME}" \
    --email "${BOOKSTACK_ADMIN_EMAIL}" \
    --password "${BOOKSTACK_ADMIN_PASSWORD}" || echo "Falha ao criar admin (MVP)."

  API_CREDS=$(php /app/www/artisan bookstack:api-token:create "${BOOKSTACK_ADMIN_EMAIL}" seed-token 2>/dev/null || true)
  API_ID=$(printf '%s' "$API_CREDS" | sed -n 's/.*Token ID:[[:space:]]*//p' | head -n1)
  API_SECRET=$(printf '%s' "$API_CREDS" | sed -n 's/.*Token Secret:[[:space:]]*//p' | head -n1)

  if [ -n "$API_ID" ] && [ -n "$API_SECRET" ]; then
    export BOOKSTACK_API_TOKEN_ID="$API_ID"
    export BOOKSTACK_API_TOKEN_SECRET="$API_SECRET"
    export BOOKSTACK_API_URL="http://127.0.0.1"
    python3 /config/www/scripts/seed_bookstack.py /config/www/seed/manual_banco_mercado.json || \
      echo "Seed falhou (MVP): seguindo execução sem bloquear startup."
  else
    echo "Token de API não gerado; seed não será executado (MVP)."
  fi
) &

echo "Iniciando /init como PID 1..."
exec /init
