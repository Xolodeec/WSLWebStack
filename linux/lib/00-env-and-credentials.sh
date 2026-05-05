# Sourced by Provision-WslWebStack.sh — repo paths, secrets, credential stubs.
# All variables remain in the same shell as modules (no subshell isolation).

REPO_ROOT="$(cd "$LINUX_DIR/.." && pwd)"
STATE_DIR="${WSL_STATE_DIR:-$REPO_ROOT/.wsl-state}"
CREDS_DIR="${WSL_CREDS_DIR:-$REPO_ROOT/credentials}"
mkdir -p "$STATE_DIR" "$CREDS_DIR" "$REPO_ROOT/assets"
chmod 700 "$CREDS_DIR" 2>/dev/null || true

: "${WSL_DOMAIN:=localhost}"
: "${SSL_MODE:=local}"
# Кэш архива только в assets/; при отсутствии файла модуль 40 скачивает его с phpmyadmin.net
: "${PMA_TAR:=$REPO_ROOT/assets/phpMyAdmin-5.2.1-all-languages.tar.gz}"
: "${RABBITMQ_USER:=rabbitadmin}"

export WSL_DOMAIN SSL_MODE PMA_TAR RABBITMQ_USER

read_or_create_line2_secret() {
    local f="$1"
    if [ -f "$f" ]; then
        sed -n '2p' "$f" | tr -d '\r\n'
        return
    fi
    local s
    s=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 28)
    umask 077
    {
        echo "# Generated on $(date -Iseconds), password on line 2."
        echo "$s"
    } >"$f"
    chmod 600 "$f"
    printf '%s' "$s"
}

normalize_two_line_secret() {
    local f="$1" comment="$2"
    local pass
    pass=$(sed -n '2p' "$f" | tr -d '\r\n')
    umask 077
    {
        echo "# $comment"
        echo "$pass"
    } >"$f"
    chmod 600 "$f"
}

DOMAIN="$WSL_DOMAIN"
SITE_DB_NAME=$(echo "$DOMAIN" | tr -d '.-' | cut -c1-32)

DB_ROOT_PASS=$(read_or_create_line2_secret "$CREDS_DIR/mysql-root.txt")
UP_DB_PASS=$(read_or_create_line2_secret "$CREDS_DIR/mysql-up.txt")
PMA_APP_PASS=$(read_or_create_line2_secret "$CREDS_DIR/mysql-phpmyadmin.txt")
RABBITMQ_ADMIN_PASS=$(read_or_create_line2_secret "$CREDS_DIR/rabbitmq.txt")

normalize_two_line_secret "$CREDS_DIR/mysql-root.txt" "MySQL root@localhost."
normalize_two_line_secret "$CREDS_DIR/mysql-phpmyadmin.txt" "MySQL phpmyadmin@localhost service account."
normalize_two_line_secret "$CREDS_DIR/mysql-up.txt" "MySQL up@localhost | DB: $SITE_DB_NAME."
normalize_two_line_secret "$CREDS_DIR/rabbitmq.txt" "RabbitMQ user=${RABBITMQ_USER} | http://127.0.0.1:15672/"

cat >"$CREDS_DIR/_README.txt" <<EOF
Generated credentials:
  mysql-root.txt
  mysql-up.txt
  mysql-phpmyadmin.txt
  rabbitmq.txt

Password is always on line 2.
EOF
chmod 600 "$CREDS_DIR/_README.txt"

echo "Repo root: $REPO_ROOT"
echo "Base domain: $DOMAIN"
echo "Credentials dir: $CREDS_DIR"
