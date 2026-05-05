# Base site restart + service-access.txt
systemctl restart apache2

BASE_URL="https://${WSL_DOMAIN:-localhost}/"

cat >"$CREDS_DIR/service-access.txt" <<EOF
Base site: $BASE_URL
phpMyAdmin: ${BASE_URL}phpmyadmin
RabbitMQ: http://127.0.0.1:15672/ (user: $RABBITMQ_USER, password in rabbitmq.txt line 2)
MySQL root password: mysql-root.txt line 2
MySQL app user up password: mysql-up.txt line 2

Cloudflare Tunnel (cloudflared) is installed in WSL. On ${BASE_URL} use "Quick Tunnel" per domain.
Logs: /var/lib/uchet-tunnel/<name>_local.log | systemctl status uchet-quick-tunnel@<name>_local
EOF
chmod 600 "$CREDS_DIR/service-access.txt"
