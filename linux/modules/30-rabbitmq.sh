# RabbitMQ + management plugin + admin user.
# WSL / cloned distros: broken Mnesia or /etc/hosts without the machine name breaks Erlang (rabbit@HOST).

echo "Installing RabbitMQ..."
apt-get install -y rabbitmq-server

ensure_hosts_for_erlang() {
    # Erlang distribution resolves the short hostname; if only "localhost" exists, rabbit@PC never starts.
    local fqdn short line
    fqdn=$(hostname -f 2>/dev/null || hostname)
    short=$(hostname -s 2>/dev/null || hostname)
    [ -n "$short" ] || return 0
    if grep -qE "^127\.0\.0\.1[[:space:]].*[[:space:]]${short}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
        return 0
    fi
    line="127.0.0.1 $short $fqdn"
    echo "$line" >>/etc/hosts
    echo "RabbitMQ: added to /etc/hosts: $line" >&2
}

rabbitmq_running() {
    rabbitmqctl -q status >/dev/null 2>&1
}

try_start_rabbit() {
    ensure_hosts_for_erlang
    systemctl enable rabbitmq-server 2>/dev/null || true
    systemctl reset-failed rabbitmq-server.service 2>/dev/null || true
    systemctl stop rabbitmq-server 2>/dev/null || true
    sleep 1
    systemctl start rabbitmq-server.service || true
    sleep 2
    local i max=25
    echo "RabbitMQ: waiting for node (up to ${max}s)..." >&2
    for i in $(seq 1 "$max"); do
        if rabbitmqctl await_startup >/dev/null 2>&1; then
            echo "RabbitMQ: node is up." >&2
            return 0
        fi
        if rabbitmq_running; then
            echo "RabbitMQ: node is up." >&2
            return 0
        fi
        if [ $((i % 5)) -eq 0 ]; then
            echo "RabbitMQ: still waiting... ${i}/${max}" >&2
        fi
        sleep 1
    done
    return 1
}

if ! try_start_rabbit; then
    echo "RabbitMQ did not start; clearing Mnesia (node DB) and retrying once..." >&2
    systemctl stop rabbitmq-server 2>/dev/null || true
    rm -rf /var/lib/rabbitmq/mnesia/*
    chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
    try_start_rabbit || true
fi

if ! rabbitmq_running; then
    echo "WARNING: RabbitMQ is still not running; skipping plugin and user setup. Web stack will continue." >&2
    echo "WARNING: Check: systemctl status rabbitmq-server --no-pager; journalctl -u rabbitmq-server -n 40 --no-pager" >&2
else
    rabbitmq-plugins enable rabbitmq_management >/dev/null 2>&1 || true
    rabbitmqctl await_startup >/dev/null 2>&1 || sleep 2
    rabbitmqctl add_user "$RABBITMQ_USER" "$RABBITMQ_ADMIN_PASS" 2>/dev/null || rabbitmqctl change_password "$RABBITMQ_USER" "$RABBITMQ_ADMIN_PASS" || true
    rabbitmqctl set_user_tags "$RABBITMQ_USER" administrator || true
    rabbitmqctl set_permissions -p / "$RABBITMQ_USER" ".*" ".*" ".*" || true
fi
