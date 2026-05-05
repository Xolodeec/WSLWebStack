<?php
declare(strict_types=1);

session_start();
if (empty($_SESSION['csrf'])) {
    $_SESSION['csrf'] = bin2hex(random_bytes(16));
}
$csrf = $_SESSION['csrf'];

$error = $_GET['error'] ?? '';
$ok = $_GET['ok'] ?? '';
$tunnelFlash = $_SESSION['tunnel_flash'] ?? '';
unset($_SESSION['tunnel_flash']);

$files = glob('/etc/apache2/sites-available/*.local.conf') ?: [];
$domains = [];
foreach ($files as $file) {
    $name = basename($file, '.conf');
    if (preg_match('/^[a-z0-9-]+\.local$/', $name)) {
        $domains[] = $name;
    }
}
sort($domains);

function tunnel_status_row(string $domain): array
{
    $cmd = 'sudo /usr/local/bin/wslwebstack-tunnel.sh status ' . escapeshellarg($domain) . ' 2>/dev/null';
    $line = @shell_exec($cmd);
    if ($line === null || $line === '') {
        return ['active' => false, 'url' => ''];
    }
    $line = trim($line);
    $tab = strpos($line, "\t");
    if ($tab === false) {
        return ['active' => false, 'url' => ''];
    }
    $state = substr($line, 0, $tab);
    $url = substr($line, $tab + 1);
    return ['active' => $state === 'active', 'url' => $url];
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>WSLWebStack — Local domains</title>
  <style>body{font-family:Arial,sans-serif;margin:24px}input,button{padding:8px}li{margin:10px 0}.ok{color:#0a7d20}.err{color:#a50000}.warn{color:#8a5b00}.muted{color:#444;font-size:0.9em}.tunnel{margin-top:6px}</style>
</head>
<body>
  <h1>Registered domains</h1>
  <?php if ($ok): ?><p class="ok"><?= htmlspecialchars($ok, ENT_QUOTES, 'UTF-8') ?></p><?php endif; ?>
  <?php if ($error): ?><p class="err"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></p><?php endif; ?>
  <?php if ($tunnelFlash): ?><p class="ok"><?= nl2br(htmlspecialchars($tunnelFlash, ENT_QUOTES, 'UTF-8')) ?></p><?php endif; ?>
  <p class="muted">Cloudflare Quick Tunnel: публичный <code>*.trycloudflare.com</code> меняется после перезапуска туннеля. Для постоянного URL нужен named tunnel в вашем аккаунте Cloudflare.</p>
  <p class="warn"><strong>Внимание:</strong> пока туннель включён, выбранный локальный сайт доступен из интернета по выданной ссылке. Не включайте на публичный URL то, что не готовы показать третьим лицам.</p>
  <ul>
    <?php foreach ($domains as $domain):
        $t = tunnel_status_row($domain);
        ?>
      <li>
        <a href="https://<?= htmlspecialchars($domain, ENT_QUOTES, 'UTF-8') ?>/" target="_blank"><?= htmlspecialchars($domain, ENT_QUOTES, 'UTF-8') ?></a>
        <div class="tunnel">
          <?php if ($t['url'] !== ''): ?>
            <span class="muted">Публично:</span>
            <a href="<?= htmlspecialchars($t['url'], ENT_QUOTES, 'UTF-8') ?>" target="_blank" rel="noopener"><?= htmlspecialchars($t['url'], ENT_QUOTES, 'UTF-8') ?></a>
            <?php if (!$t['active']): ?> <span class="err">(туннель остановлен — URL устарел)</span><?php endif; ?>
          <?php else: ?>
            <span class="muted">Туннель не запущен.</span>
          <?php endif; ?>
          <form method="post" action="/tunnel-action.php" style="display:inline;margin-left:8px">
            <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="domain" value="<?= htmlspecialchars($domain, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="do" value="start">
            <button type="submit">Запустить Quick Tunnel</button>
          </form>
          <form method="post" action="/tunnel-action.php" style="display:inline;margin-left:4px">
            <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="domain" value="<?= htmlspecialchars($domain, ENT_QUOTES, 'UTF-8') ?>">
            <input type="hidden" name="do" value="stop">
            <button type="submit">Остановить</button>
          </form>
        </div>
      </li>
    <?php endforeach; ?>
  </ul>

  <h2>Add domain</h2>
  <form method="post" action="/add-domain.php">
    <label>
      Name (without .local):
      <input name="name" required pattern="[a-z0-9-]{2,31}" placeholder="shopium">
    </label>
    <button type="submit">Add</button>
  </form>
</body>
</html>
