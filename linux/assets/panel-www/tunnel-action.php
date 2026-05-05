<?php
declare(strict_types=1);
session_start();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: /');
    exit;
}
$csrf = (string)($_POST['csrf'] ?? '');
if ($csrf === '' || !hash_equals($_SESSION['csrf'] ?? '', $csrf)) {
    header('Location: /?error=' . rawurlencode('Bad CSRF token; reload the page.'));
    exit;
}
$domain = strtolower(trim((string)($_POST['domain'] ?? '')));
if (!preg_match('/^[a-z0-9-]+\.local$/', $domain)) {
    header('Location: /?error=' . rawurlencode('Invalid domain'));
    exit;
}
if (!is_file('/etc/apache2/sites-available/' . $domain . '.conf')) {
    header('Location: /?error=' . rawurlencode('Unknown domain'));
    exit;
}
$do = $_POST['do'] ?? '';
if ($do === 'start') {
    $cmd = 'sudo /usr/local/bin/wslwebstack-tunnel.sh start ' . escapeshellarg($domain) . ' 2>&1';
    $out = [];
    $code = 0;
    exec($cmd, $out, $code);
    $msg = trim(implode("\n", $out));
    if ($code !== 0) {
        header('Location: /?error=' . rawurlencode($msg !== '' ? $msg : 'Tunnel start failed'));
        exit;
    }
    $_SESSION['tunnel_flash'] = 'Туннель для ' . $domain . ":\n" . $msg;
    header('Location: /');
    exit;
}
if ($do === 'stop') {
    $cmd = 'sudo /usr/local/bin/wslwebstack-tunnel.sh stop ' . escapeshellarg($domain) . ' 2>&1';
    $out = [];
    $code = 0;
    exec($cmd, $out, $code);
    $_SESSION['tunnel_flash'] = 'Туннель для ' . $domain . ' остановлен.';
    header('Location: /');
    exit;
}
header('Location: /?error=' . rawurlencode('Unknown action'));
