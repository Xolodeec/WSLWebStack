# APT base, Ondrej PHP PPA, Apache + PHP 8.3 modules.

rm -f /etc/apt/sources.list.d/mysql.list
# Cloudflare repo is added only in 95-cloudflare-tunnel.sh. A leftover broken list breaks apt here.
if ! command -v cloudflared >/dev/null 2>&1; then
    rm -f /etc/apt/sources.list.d/cloudflared.list
    rm -f /usr/share/keyrings/cloudflare-main.gpg
fi
export DEBIAN_FRONTEND=noninteractive
# If a previous run or import left dpkg half-done, apt refuses until this completes.
dpkg --configure -a
apt-get update -qq
apt-get purge -y 'php7.*' 'mariadb-server*' 2>/dev/null || true
apt-get autoclean -qq
apt-get autoremove -y -qq

apt-get install -y software-properties-common wget curl zip unzip git apache2
add-apt-repository -y ppa:ondrej/php
apt-get update -qq

a2enmod rewrite headers ssl alias >/dev/null 2>&1 || true

apt-get install -y \
    php8.3 php8.3-common php8.3-mysql php8.3-xml php8.3-curl php8.3-gd php8.3-cli php8.3-dev \
    php8.3-mbstring php8.3-opcache php8.3-zip php8.3-intl libapache2-mod-php8.3
update-alternatives --set php /usr/bin/php8.3 2>/dev/null || true
