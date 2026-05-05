# phpMyAdmin: download archive if missing, then DB user + /etc/phpmyadmin/config.inc.php

echo "Installing phpMyAdmin..."
PMA_VERSION="${PMA_VERSION:-5.2.1}"
PMA_BASENAME="phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz"
PMA_URL="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/${PMA_BASENAME}"

if [ ! -f "$PMA_TAR" ]; then
    mkdir -p "$(dirname "$PMA_TAR")"
    echo "Downloading ${PMA_BASENAME}..."
    if ! curl -fsSL "$PMA_URL" -o "${PMA_TAR}.part"; then
        rm -f "${PMA_TAR}.part"
        echo "ERROR: download failed: $PMA_URL"
        echo "Need network, or copy ${PMA_BASENAME} into $(dirname "$PMA_TAR")/ manually."
        exit 1
    fi
    mv "${PMA_TAR}.part" "$PMA_TAR"
fi
if [ ! -f /usr/share/phpmyadmin/index.php ]; then
    cd /usr/share/
    rm -rf phpmyadmin
    tar xzf "$PMA_TAR"
    PMA_DIR=$(ls -d phpMyAdmin-* 2>/dev/null | head -1 || true)
    [ -n "$PMA_DIR" ] || { echo "Cannot locate phpMyAdmin dir after extraction"; exit 1; }
    mv "$PMA_DIR" phpmyadmin
fi
mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS phpmyadmin CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'phpmyadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$PMA_APP_PASS';
ALTER USER 'phpmyadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$PMA_APP_PASS';
GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'phpmyadmin'@'localhost';
FLUSH PRIVILEGES;
EOF
[ -f /usr/share/phpmyadmin/sql/create_tables.sql ] && mysql -u root -p"$DB_ROOT_PASS" phpmyadmin < /usr/share/phpmyadmin/sql/create_tables.sql || true
mkdir -p /etc/phpmyadmin
BF_SECRET=$(openssl rand -base64 32)
cat > /etc/phpmyadmin/config.inc.php <<EOF
<?php
\$cfg['blowfish_secret'] = '$BF_SECRET';
\$i = 1;
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['controluser'] = 'phpmyadmin';
\$cfg['Servers'][\$i]['controlpass'] = '$PMA_APP_PASS';
\$cfg['Servers'][\$i]['pmadb'] = 'phpmyadmin';
?>
EOF
