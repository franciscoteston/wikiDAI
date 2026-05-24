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
USE_DATA_FOR_DB="${USE_DATA_FOR_DB:-false}"
PERSISTENT_DB_DIR="${PERSISTENT_DB_DIR:-/data/wikidai-mariadb}"
PERSISTENT_CONFIG_DIR="${PERSISTENT_CONFIG_DIR:-/data/wikidai-bookstack}"

export APP_URL="${APP_URL:-https://franciscoteston-wikidai.hf.space}"
export APP_KEY="${APP_KEY:-}"
export BOOKSTACK_ADMIN_NAME="${BOOKSTACK_ADMIN_NAME:-}"
export BOOKSTACK_ADMIN_EMAIL="${BOOKSTACK_ADMIN_EMAIL:-}"
export BOOKSTACK_ADMIN_PASSWORD="${BOOKSTACK_ADMIN_PASSWORD:-}"

if [ -z "${APP_KEY:-}" ]; then
  echo "ERRO: APP_KEY não definida. Configure APP_KEY como Secret no Hugging Face Space."
  exit 1
fi

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

if [ "${USE_DATA_FOR_DB}" = "true" ]; then
  if [ ! -d "/data" ]; then
    echo "ERRO: USE_DATA_FOR_DB=true, mas /data não existe."
    echo "Fallback recomendado: USE_DATA_FOR_DB=false para usar banco efêmero em /tmp/wikidai-mariadb."
    exit 1
  fi

  DB_DIR="$PERSISTENT_DB_DIR"
  echo "Persistência via Storage Bucket ativada."
  echo "DB_DIR=$DB_DIR"
  echo "PERSISTENT_CONFIG_DIR=$PERSISTENT_CONFIG_DIR"

  mkdir -p "$PERSISTENT_CONFIG_DIR" "$PERSISTENT_CONFIG_DIR/uploads" "$PERSISTENT_CONFIG_DIR/files" "$PERSISTENT_CONFIG_DIR/images" "$PERSISTENT_CONFIG_DIR/themes" "$PERSISTENT_CONFIG_DIR/framework/cache" "$PERSISTENT_CONFIG_DIR/framework/sessions" "$PERSISTENT_CONFIG_DIR/framework/views" "$PERSISTENT_CONFIG_DIR/framework/purifier" "$PERSISTENT_CONFIG_DIR/backups" "$PERSISTENT_CONFIG_DIR/log/bookstack"
  chmod -R 777 "$PERSISTENT_CONFIG_DIR" || true
  chown -R abc:abc "$PERSISTENT_CONFIG_DIR" || true
else
  DB_DIR="/tmp/wikidai-mariadb"
  echo "Persistência do banco desativada; usando banco efêmero em /tmp."
fi

mkdir -p "$DB_DIR"
chmod 777 "$DB_DIR" || true
chown -R mysql:mysql "$DB_DIR" || true
chmod -R 700 "$DB_DIR" || true

if [ "${RESET_DB_ON_START:-false}" = "true" ]; then
  echo "ATENÇÃO FORTE: RESET_DB_ON_START=true; apagando TODO o banco MariaDB em $DB_DIR"
  echo "ATENÇÃO FORTE: com USE_DATA_FOR_DB=true isso apaga o banco persistente no Storage Bucket."
  if [ -S "$MYSQL_SOCKET" ]; then
    mariadb-admin --protocol=socket -S "$MYSQL_SOCKET" -uroot shutdown >/dev/null 2>&1 || true
  fi
  rm -rf "$DB_DIR"
  mkdir -p "$DB_DIR"
  chmod 777 "$DB_DIR" || true
  chown -R mysql:mysql "$DB_DIR" || true
  chmod -R 700 "$DB_DIR" || true
fi

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
  if [ "${USE_DATA_FOR_DB}" = "true" ]; then
    echo "Se houver erro de permissão (ex.: InnoDB OS error 13), use fallback: USE_DATA_FOR_DB=false."
  fi
  exit 1
fi
echo "MariaDB disponível."
ROOT_AUTH_MODE=""
if mariadb --protocol=socket -S "$MYSQL_SOCKET" -uroot --password="${DB_ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
  ROOT_AUTH_MODE="password"
  echo "Autenticação root MariaDB: usando senha existente."
elif mariadb --protocol=socket -S "$MYSQL_SOCKET" -uroot -e "SELECT 1" >/dev/null 2>&1; then
  ROOT_AUTH_MODE="no_password"
  echo "Autenticação root MariaDB: sem senha inicial; definindo DB_ROOT_PASSWORD."
else
  echo "ERRO: não foi possível autenticar como root no MariaDB. Verifique DB_ROOT_PASSWORD ou reinicialize o banco."
  exit 1
fi

echo "Criando banco e usuário..."
if [ "$ROOT_AUTH_MODE" = "password" ]; then
  mariadb --protocol=socket -S "$MYSQL_SOCKET" -uroot --password="${DB_ROOT_PASSWORD}" <<SQL
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
else
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
fi

mkdir -p /config/www/uploads /config/www/files /config/www/images /config/www/themes /config/www/framework/cache /config/www/framework/sessions /config/www/framework/views /config/www/framework/purifier /config/backups /config/log/bookstack

touch /config/log/bookstack/laravel.log
chown -R abc:abc /config/www /config/backups /config/log/bookstack || true
chmod -R ug+rwX /config/www /config/backups /config/log/bookstack || true

if [ "${USE_DATA_FOR_DB}" = "true" ]; then
  echo "Aplicando symlinks seletivos de persistência para BookStack..."
  rm -rf /config/www/uploads /config/www/files /config/www/images /config/backups
  ln -s "$PERSISTENT_CONFIG_DIR/uploads" /config/www/uploads
  ln -s "$PERSISTENT_CONFIG_DIR/files" /config/www/files
  ln -s "$PERSISTENT_CONFIG_DIR/images" /config/www/images
  ln -s "$PERSISTENT_CONFIG_DIR/backups" /config/backups
fi

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
upsert_env_var "APP_ENV" "${APP_ENV:-production}" "/config/www/.env"
upsert_env_var "APP_DEBUG" "${APP_DEBUG:-false}" "/config/www/.env"
upsert_env_var "DB_HOST" "127.0.0.1" "/config/www/.env"
upsert_env_var "DB_PORT" "3306" "/config/www/.env"
upsert_env_var "DB_DATABASE" "${DB_DATABASE}" "/config/www/.env"
upsert_env_var "DB_USERNAME" "${DB_USERNAME}" "/config/www/.env"
upsert_env_var "DB_PASSWORD" "${DB_PASSWORD}" "/config/www/.env"
upsert_env_var "DB_SOCKET" "" "/config/www/.env"
upsert_env_var "LOG_CHANNEL" "stderr" "/config/www/.env"

RUN_CREATE_ADMIN=0
if [ -n "$BOOKSTACK_ADMIN_EMAIL" ] || [ -n "$BOOKSTACK_ADMIN_PASSWORD" ]; then
  if [ -z "$BOOKSTACK_ADMIN_EMAIL" ] || [ -z "$BOOKSTACK_ADMIN_PASSWORD" ]; then
    echo "ERRO: Defina BOOKSTACK_ADMIN_EMAIL e BOOKSTACK_ADMIN_PASSWORD juntos para criar admin customizado."
  elif ! printf '%s' "$BOOKSTACK_ADMIN_EMAIL" | grep -q '@'; then
    echo "ERRO: BOOKSTACK_ADMIN_EMAIL inválido. O valor deve conter '@'."
  elif [ "$(printf '%s' "$BOOKSTACK_ADMIN_PASSWORD" | wc -c)" -lt 8 ]; then
    echo "ERRO: BOOKSTACK_ADMIN_PASSWORD inválido. A senha deve ter no mínimo 8 caracteres."
  else
    RUN_CREATE_ADMIN=1
  fi
fi

(
  echo "Processo auxiliar: aguardando BookStack responder localmente..."
  BOOKSTACK_READY=0
  for i in $(seq 1 300); do
    if command -v curl >/dev/null 2>&1; then
      if curl -fsS "http://127.0.0.1/api/docs" >/dev/null 2>&1 || curl -fsS "http://127.0.0.1" >/dev/null 2>&1; then
        BOOKSTACK_READY=1
        break
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -O - "http://127.0.0.1/api/docs" >/dev/null 2>&1 || wget -q -O - "http://127.0.0.1" >/dev/null 2>&1; then
        BOOKSTACK_READY=1
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
        BOOKSTACK_READY=1
        break
      fi
    fi
    sleep 1
  done

  if [ "$BOOKSTACK_READY" -ne 1 ]; then
    echo "BookStack não respondeu localmente a tempo; ignorando bootstrap de admin/seed (MVP)."
    exit 0
  fi

  echo "BookStack respondeu localmente; iniciando proxy 7860 -> 80..."
  socat TCP-LISTEN:7860,fork,reuseaddr TCP:127.0.0.1:80 &

  echo "Proxy iniciado; executando bootstrap de admin/seed..."

  if [ "$RUN_CREATE_ADMIN" -eq 1 ]; then
    set +e
    ADMIN_CREATE_OUTPUT=$(php /app/www/artisan bookstack:create-admin       --name "${BOOKSTACK_ADMIN_NAME:-Admin}"       --email "${BOOKSTACK_ADMIN_EMAIL}"       --password "${BOOKSTACK_ADMIN_PASSWORD}" 2>&1)
    ADMIN_CREATE_STATUS=$?
    set -e
    printf '%s\n' "$ADMIN_CREATE_OUTPUT"

    if [ "$ADMIN_CREATE_STATUS" -eq 0 ]; then
      echo "Admin customizado criado com sucesso."
    elif printf '%s' "$ADMIN_CREATE_OUTPUT" | grep -Eiq 'already exists|já existe'; then
      echo "Admin já existe; seguindo."
    else
      echo "Falha ao criar admin customizado; seguindo startup."
    fi
  else
    echo "Admin customizado não configurado; usando admin padrão do BookStack em instalação fresca."
  fi

  if [ -n "${BOOKSTACK_API_TOKEN_ID:-}" ] && [ -n "${BOOKSTACK_API_TOKEN_SECRET:-}" ]; then
    export BOOKSTACK_API_URL="http://127.0.0.1"
    python3 /config/www/scripts/seed_bookstack.py /config/www/seed/manual_banco_mercado.json || \
      echo "Seed falhou (MVP): seguindo execução sem bloquear startup."
  else
    echo "BOOKSTACK_API_TOKEN_ID/SECRET não configurados; seed não executado."
  fi
) &

echo "Iniciando /init como PID 1..."
exec /init
