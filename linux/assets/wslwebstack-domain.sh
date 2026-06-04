#!/bin/bash
set -euo pipefail

ACTION="${1:-}"
NAME="${2:-}"
[ -n "$ACTION" ] || { echo "Usage: wslwebstack-domain.sh {add|remove} <name> [ssl_mode]"; exit 1; }
[ -n "$NAME" ] || { echo "Domain name is required"; exit 1; }
SSL_MODE="${3:-local}"

if [[ ! "$NAME" =~ ^[a-z0-9][a-z0-9-]{1,30}$ ]]; then
    echo "Invalid name: use [a-z0-9-], 2-31 chars."
    exit 1
fi

DOMAIN="${NAME}.local"
ROOT="/var/www/${DOMAIN}"
SITE_AVAIL="/etc/apache2/sites-available/${DOMAIN}.conf"
CRT="/etc/ssl/wsl/${DOMAIN}.crt"
KEY="/etc/ssl/wsl/${DOMAIN}.key"
TUNNEL_INST="${NAME}_local"

if [ "$ACTION" = "remove" ]; then
    systemctl disable --now "wslwebstack-quick-tunnel@${TUNNEL_INST}.service" 2>/dev/null || true
    rm -f "/var/lib/wslwebstack-tunnel/${TUNNEL_INST}.public_url" \
        "/var/lib/wslwebstack-tunnel/${TUNNEL_INST}.log" 2>/dev/null || true
    a2dissite "${DOMAIN}.conf" 2>/dev/null || true
    rm -f "$SITE_AVAIL" "/etc/apache2/sites-enabled/${DOMAIN}.conf"
    systemctl reload apache2
    echo "removed vhost $DOMAIN"
    exit 0
fi

if [ "$ACTION" != "add" ]; then
    echo "Unknown action: $ACTION (use add or remove)"
    exit 1
fi

mkdir -p "$ROOT"
if [ ! -f "$ROOT/index.php" ]; then
    cat >"$ROOT/index.php" <<PHP
<?php
echo "<h1>${DOMAIN} created</h1>";
echo "<p>Directory: ${ROOT}</p>";
PHP
fi
chown -R www-data:www-data "$ROOT"
find "$ROOT" -type d -exec chmod 775 {} \;
find "$ROOT" -type f -exec chmod 664 {} \;

if [ "$SSL_MODE" = "local" ]; then
    mkdir -p /etc/ssl/wsl
    if [ ! -f "$CRT" ] || [ ! -f "$KEY" ]; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$KEY" -out "$CRT" \
            -subj "/CN=${DOMAIN}/O=WSLWebStack/C=RU" >/dev/null 2>&1
    fi
    cat >"$SITE_AVAIL" <<APACHE
<VirtualHost *:80>
    ServerName ${DOMAIN}
    Redirect permanent / https://${DOMAIN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${DOMAIN}
    DocumentRoot ${ROOT}

    <Directory ${ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile ${CRT}
    SSLCertificateKeyFile ${KEY}
</VirtualHost>
APACHE
else
    cat >"$SITE_AVAIL" <<APACHE
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${ROOT}
    <Directory ${ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
APACHE
fi

a2ensite "${DOMAIN}.conf" >/dev/null 2>&1 || true
systemctl reload apache2
echo "$DOMAIN"
