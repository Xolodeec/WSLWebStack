#!/bin/bash
# WSL dev: add human user to www-data group; site tree stays www-data:www-data + setgid dirs.
# shellcheck shell=bash

wslwebstack_resolve_dev_user() {
    if [ -n "${WSLWEBSTACK_DEV_USER:-}" ] && id "${WSLWEBSTACK_DEV_USER}" &>/dev/null; then
        echo "$WSLWEBSTACK_DEV_USER"
        return 0
    fi
    if [ -f /etc/wslwebstack/dev-user ]; then
        local u
        u=$(tr -d '\r\n' </etc/wslwebstack/dev-user)
        if [ -n "$u" ] && id "$u" &>/dev/null; then
            echo "$u"
            return 0
        fi
    fi
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] && [ "$SUDO_USER" != www-data ] && id "$SUDO_USER" &>/dev/null; then
        echo "$SUDO_USER"
        return 0
    fi
    getent passwd | awk -F: '$3>=1000 && $3<65534 && $6 ~ /^\/home\// {print $1; exit}'
}

# Called once at provision: who gets group www-data (not re-detected per new domain).
wslwebstack_register_dev_user() {
    local u
    u=$(wslwebstack_resolve_dev_user)
    [ -n "$u" ] || return 0
    mkdir -p /etc/wslwebstack
    echo "$u" >/etc/wslwebstack/dev-user
    chmod 644 /etc/wslwebstack/dev-user
    if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx www-data; then
        echo "WSLWebStack: $u already in group www-data." >&2
        return 0
    fi
    usermod -aG www-data "$u" 2>/dev/null || true
    echo "WSLWebStack: $u added to group www-data — re-open WSL terminal (or wsl --shutdown)." >&2
}

wslwebstack_apply_site_perms() {
    local root="$1"
    [ -d "$root" ] || return 1
    chown -R www-data:www-data "$root"
    find "$root" -type d -exec chmod 2775 {} \;
    find "$root" -type f -exec chmod 664 {} \;
}
