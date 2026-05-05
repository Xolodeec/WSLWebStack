# MySQL 8 server, root password, app DB and user `up`.

echo "Installing MySQL 8..."
apt-get install -y mysql-server
MYSQL_MARKER="$STATE_DIR/mysql_root_configured"

# Fresh Ubuntu MySQL: root@localhost uses auth_socket — set password without a second mysqld (avoids OOM "Killed" on tight WSL RAM).
try_set_root_password_via_socket() {
    systemctl start mysql 2>/dev/null || true
    sleep 2
    if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS'; FLUSH PRIVILEGES;"
        return 0
    fi
    return 1
}

reset_mysql_root() {
    if try_set_root_password_via_socket; then
        return 0
    fi
    systemctl stop mysql || true
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld
    # Lower footprint so WSL2 is less likely to OOM-kill this extra mysqld.
    mysqld_safe --skip-grant-tables --skip-networking --innodb_buffer_pool_size=32M --performance_schema=OFF &
    sleep 8
    mysql -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS';" || true
    killall -9 mysqld_safe mysqld 2>/dev/null || true
    sleep 2
    systemctl start mysql
    sleep 2
}
if [ -f "$MYSQL_MARKER" ]; then
    mysql -u root -p"$DB_ROOT_PASS" -e "SELECT 1" >/dev/null 2>&1 || { rm -f "$MYSQL_MARKER"; reset_mysql_root; }
else
    reset_mysql_root
fi
mysql -u root -p"$DB_ROOT_PASS" -e "SELECT 1" >/dev/null 2>&1
touch "$MYSQL_MARKER"

mysql -u root -p"$DB_ROOT_PASS" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS $SITE_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'up'@'localhost' IDENTIFIED WITH mysql_native_password BY '$UP_DB_PASS';
ALTER USER 'up'@'localhost' IDENTIFIED WITH mysql_native_password BY '$UP_DB_PASS';
GRANT ALL PRIVILEGES ON *.* TO 'up'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
