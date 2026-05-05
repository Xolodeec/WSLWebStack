<?php
declare(strict_types=1);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: /');
    exit;
}
$name = strtolower(trim((string)($_POST['name'] ?? '')));
if (!preg_match('/^[a-z0-9][a-z0-9-]{1,30}$/', $name)) {
    header('Location: /?error=' . rawurlencode('Invalid domain name'));
    exit;
}
$sslMode = getenv('SSL_MODE') ?: 'local';
$cmd = 'sudo /usr/local/bin/wslwebstack-domain.sh add '
    . escapeshellarg($name)
    . ' '
    . escapeshellarg($sslMode)
    . ' 2>&1';
$output = [];
$code = 0;
exec($cmd, $output, $code);
if ($code !== 0) {
    header('Location: /?error=' . rawurlencode(implode("\n", $output)));
    exit;
}
header('Location: /?ok=' . rawurlencode($name . '.local created'));
