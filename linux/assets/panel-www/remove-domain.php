<?php
declare(strict_types=1);

session_start();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: /');
    exit;
}

$csrf = (string)($_POST['csrf'] ?? '');
if ($csrf === '' || !hash_equals($_SESSION['csrf'] ?? '', $csrf)) {
    header('Location: /?error=' . rawurlencode('Неверный CSRF-токен; обновите страницу.'));
    exit;
}

$domain = strtolower(trim((string)($_POST['domain'] ?? '')));
if (!preg_match('/^[a-z0-9-]+\.local$/', $domain)) {
    header('Location: /?error=' . rawurlencode('Некорректное имя домена'));
    exit;
}

$name = substr($domain, 0, -strlen('.local'));
$conf = '/etc/apache2/sites-available/' . $domain . '.conf';
if (!is_file($conf)) {
    header('Location: /?error=' . rawurlencode('Конфигурация Apache для домена не найдена'));
    exit;
}

$cmd = 'sudo /usr/local/bin/wslwebstack-domain.sh remove '
    . escapeshellarg($name)
    . ' 2>&1';
$output = [];
$code = 0;
exec($cmd, $output, $code);
if ($code !== 0) {
    header('Location: /?error=' . rawurlencode(implode("\n", $output)));
    exit;
}

header('Location: /?ok=' . rawurlencode('Конфигурация ' . $domain . ' удалена'));
exit;
