# Apache alias so phpMyAdmin is served under the base site /phpmyadmin

cat > /etc/apache2/conf-available/phpmyadmin-uchet-alias.conf <<'EOF'
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
</Directory>
EOF
a2enconf phpmyadmin-uchet-alias >/dev/null 2>&1 || true
systemctl reload apache2 2>/dev/null || true
