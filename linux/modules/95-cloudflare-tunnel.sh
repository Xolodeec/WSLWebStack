# Cloudflare Tunnel: cloudflared package, quick-tunnel scripts, systemd, sudoers.
# Runs after the base site (module 60+) so a blocked Cloudflare repo does not skip the web UI.

echo "Installing cloudflared (Cloudflare Tunnel)..."
install_cloudflared_pkg() {
    mkdir -p --mode=0755 /usr/share/keyrings
    # Cloudflare (pkg.cloudflare.com, key rollover Oct 2025): install the keyring file as shipped.
    # piping through gpg --dearmor produced incomplete key material for apt on some systems (NO_PUBKEY / "not signed").
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
    chmod 644 /usr/share/keyrings/cloudflare-main.gpg
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' >/etc/apt/sources.list.d/cloudflared.list
    apt-get update -qq
    apt-get install -y cloudflared
}

if ! install_cloudflared_pkg; then
    echo "WARNING: cloudflared could not be installed (network, mirror, or policy)." >&2
    echo "WARNING: Quick Tunnel buttons on https://${WSL_DOMAIN:-localhost}/ will stay unavailable until cloudflared is installed." >&2
    rm -f /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-main.gpg 2>/dev/null || true
else
    mkdir -p /var/lib/wslwebstack-tunnel
    chmod 755 /var/lib/wslwebstack-tunnel

    cat >/usr/local/bin/wslwebstack-tunnel-foreground.sh <<'EOF'
#!/bin/bash
# Runs cloudflared quick tunnel; parses public URL into /var/lib/wslwebstack-tunnel/<instance>.public_url
set -euo pipefail
INST="${1:?instance required}"
DOMAIN="$(echo "$INST" | sed 's/_local$/.local/')"
if [[ ! "$DOMAIN" =~ ^[a-z0-9-]+\.local$ ]]; then
    echo "Invalid instance $INST -> $DOMAIN" >&2
    exit 1
fi
STATEDIR=/var/lib/wslwebstack-tunnel
LOG="$STATEDIR/${INST}.log"
URLFILE="$STATEDIR/${INST}.public_url"
mkdir -p "$STATEDIR"
rm -f "$URLFILE"
: >"$LOG"
parse_stream() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line" >>"$LOG"
        if [[ "$line" =~ (https://[a-z0-9-]+\.trycloudflare\.com) ]]; then
            umask 022
            printf '%s\n' "${BASH_REMATCH[1]}" >"${URLFILE}.tmp"
            mv "${URLFILE}.tmp" "$URLFILE"
            chmod 644 "$URLFILE" 2>/dev/null || true
        fi
    done
}
cloudflared tunnel --no-autoupdate \
    --url "https://127.0.0.1:443" \
    --http-host-header "$DOMAIN" \
    --origin-server-name "$DOMAIN" \
    --no-tls-verify 2>&1 | parse_stream
exit "${PIPESTATUS[0]}"
EOF
    chmod +x /usr/local/bin/wslwebstack-tunnel-foreground.sh

    cat >/etc/systemd/system/wslwebstack-quick-tunnel@.service <<'EOF'
[Unit]
Description=Cloudflare quick tunnel (%i)
After=network-online.target apache2.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wslwebstack-tunnel-foreground.sh %i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    cat >/usr/local/bin/wslwebstack-tunnel.sh <<'EOF'
#!/bin/bash
set -euo pipefail
ACTION="${1:-}"
DOMAIN="${2:-}"
STATEDIR=/var/lib/wslwebstack-tunnel

domain_to_instance() {
    local d="$1"
    if [[ ! "$d" =~ ^[a-z0-9-]+\.local$ ]]; then
        echo "Invalid domain: $d" >&2
        exit 1
    fi
    printf '%s\n' "${d%.local}_local"
}

site_exists() {
    local d="$1"
    [ -f "/etc/apache2/sites-available/${d}.conf" ]
}

case "$ACTION" in
start)
    [ -n "$DOMAIN" ] || { echo "Usage: wslwebstack-tunnel.sh start <domain.local>"; exit 1; }
    site_exists "$DOMAIN" || { echo "No Apache vhost for $DOMAIN"; exit 1; }
    INST=$(domain_to_instance "$DOMAIN")
    systemctl enable --now "wslwebstack-quick-tunnel@${INST}.service"
    URLFILE="$STATEDIR/${INST}.public_url"
    for _ in $(seq 1 20); do
        if [ -f "$URLFILE" ] && [ -s "$URLFILE" ]; then
            cat "$URLFILE"
            exit 0
        fi
        sleep 1
    done
    if systemctl is-active --quiet "wslwebstack-quick-tunnel@${INST}.service"; then
        echo "Tunnel running; public URL not written yet — refresh the page in a few seconds."
    else
        echo "Tunnel failed to start. See: journalctl -u wslwebstack-quick-tunnel@${INST} -n 80 --no-pager"
        exit 1
    fi
    ;;
stop)
    [ -n "$DOMAIN" ] || { echo "Usage: wslwebstack-tunnel.sh stop <domain.local>"; exit 1; }
    INST=$(domain_to_instance "$DOMAIN")
    systemctl disable --now "wslwebstack-quick-tunnel@${INST}.service" 2>/dev/null || true
    rm -f "$STATEDIR/${INST}.public_url"
    echo "stopped"
    ;;
status)
    [ -n "$DOMAIN" ] || { echo "Usage: wslwebstack-tunnel.sh status <domain.local>"; exit 1; }
    INST=$(domain_to_instance "$DOMAIN")
    active=$(systemctl is-active "wslwebstack-quick-tunnel@${INST}.service" 2>/dev/null || echo inactive)
    url=""
    [ -f "$STATEDIR/${INST}.public_url" ] && url=$(tr -d '\r\n' <"$STATEDIR/${INST}.public_url")
    printf '%s\t%s\n' "$active" "$url"
    ;;
*)
    echo "Usage: wslwebstack-tunnel.sh {start|stop|status} <domain.local>"
    exit 1
    ;;
esac
EOF
    chmod +x /usr/local/bin/wslwebstack-tunnel.sh

    systemctl daemon-reload

    cat >/etc/sudoers.d/wslwebstack-tunnel-manager <<'EOF'
www-data ALL=(root) NOPASSWD: /usr/local/bin/wslwebstack-tunnel.sh
EOF
    chmod 440 /etc/sudoers.d/wslwebstack-tunnel-manager
fi
