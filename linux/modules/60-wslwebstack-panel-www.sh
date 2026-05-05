# Domain helper script, sudoers, panel files and base vhost (localhost by default).
# Panel files live under linux/assets/ (LF) so sourcing this script on /mnt/c is not broken by CRLF in heredocs.

ASSET_DIR="$LINUX_DIR/assets"
install -m0755 "$ASSET_DIR/wslwebstack-domain.sh" /usr/local/bin/wslwebstack-domain.sh

cat >/etc/sudoers.d/wslwebstack-domain-manager <<'WSSudoers'
www-data ALL=(root) NOPASSWD: /usr/local/bin/wslwebstack-domain.sh
WSSudoers
chmod 440 /etc/sudoers.d/wslwebstack-domain-manager

PANEL_DOMAIN="${WSL_DOMAIN:-localhost}"
PANEL_ROOT="/var/www/${PANEL_DOMAIN}"

mkdir -p "$PANEL_ROOT"
install -m0644 "$ASSET_DIR/panel-www/index.php" "$PANEL_ROOT/index.php"
install -m0644 "$ASSET_DIR/panel-www/add-domain.php" "$PANEL_ROOT/add-domain.php"
install -m0644 "$ASSET_DIR/panel-www/tunnel-action.php" "$PANEL_ROOT/tunnel-action.php"

chown -R www-data:www-data "$PANEL_ROOT"

# Register Apache vhost + SSL here so the base site works even if a later module fails.
if [ "$PANEL_DOMAIN" = "localhost" ]; then
    echo "Enabling Apache site localhost (SSL_MODE=${SSL_MODE:-local})..."
    CRT="/etc/ssl/wsl/localhost.crt"
    KEY="/etc/ssl/wsl/localhost.key"
    SITE_AVAIL="/etc/apache2/sites-available/localhost.conf"
    if [ "${SSL_MODE:-local}" = "local" ]; then
        mkdir -p /etc/ssl/wsl
        if [ ! -f "$CRT" ] || [ ! -f "$KEY" ]; then
            openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                -keyout "$KEY" -out "$CRT" \
                -subj "/CN=localhost/O=LocalWebStack/C=RU" >/dev/null 2>&1
        fi
        cat >"$SITE_AVAIL" <<APACHE
<VirtualHost *:80>
    ServerName localhost
    Redirect permanent / https://localhost/
</VirtualHost>

<VirtualHost *:443>
    ServerName localhost
    DocumentRoot ${PANEL_ROOT}

    <Directory ${PANEL_ROOT}>
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
    ServerName localhost
    DocumentRoot ${PANEL_ROOT}
    <Directory ${PANEL_ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
APACHE
    fi
    a2ensite localhost.conf >/dev/null 2>&1 || true
else
    echo "Enabling Apache site ${PANEL_DOMAIN} (SSL_MODE=${SSL_MODE:-local})..."
    /usr/local/bin/wslwebstack-domain.sh add "${PANEL_DOMAIN%.local}" "${SSL_MODE:-local}"
fi
systemctl reload apache2 2>/dev/null || systemctl restart apache2
