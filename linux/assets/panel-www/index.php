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

$domainRows = [];
$activeTunnelCount = 0;
foreach ($domains as $domain) {
    $t = tunnel_status_row($domain);
    if ($t['active']) {
        $activeTunnelCount++;
    }
    $domainRows[] = ['domain' => $domain, 'tunnel' => $t];
}
$domainCount = count($domains);

function h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
}
?>
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>WSLWebStack — Локальные домены</title>
  <style>
    :root {
      --background: #f8fafc;
      --foreground: #0f172a;
      --card: #ffffff;
      --card-foreground: #0f172a;
      --muted: #64748b;
      --muted-foreground: #64748b;
      --border: #e2e8f0;
      --input: #e2e8f0;
      --primary: #2563eb;
      --primary-foreground: #ffffff;
      --primary-soft: #eff6ff;
      --destructive: #dc2626;
      --destructive-soft: #fef2f2;
      --success: #16a34a;
      --success-soft: #f0fdf4;
      --warning: #d97706;
      --warning-soft: #fffbeb;
      --info: #2563eb;
      --info-soft: #eff6ff;
      --shadow-sm: 0 1px 2px rgb(15 23 42 / 0.05);
      --shadow-md: 0 4px 6px -1px rgb(15 23 42 / 0.08), 0 2px 4px -2px rgb(15 23 42 / 0.06);
      --radius: 0.75rem;
      --font: "Segoe UI", system-ui, -apple-system, sans-serif;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --background: #020617;
        --foreground: #f1f5f9;
        --card: #0f172a;
        --card-foreground: #f1f5f9;
        --muted: #94a3b8;
        --muted-foreground: #94a3b8;
        --border: #1e293b;
        --input: #334155;
        --primary: #3b82f6;
        --primary-soft: #172554;
        --destructive-soft: #450a0a;
        --success-soft: #052e16;
        --warning-soft: #451a03;
        --info-soft: #172554;
        --shadow-sm: 0 1px 2px rgb(0 0 0 / 0.3);
        --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.4);
      }
    }

    *, *::before, *::after { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: var(--font);
      font-size: 15px;
      line-height: 1.5;
      color: var(--foreground);
      background: var(--background);
      -webkit-font-smoothing: antialiased;
    }

    .page-bg {
      position: fixed;
      inset: 0;
      pointer-events: none;
      background: radial-gradient(ellipse 80% 50% at 50% -20%, rgb(37 99 235 / 0.12), transparent 60%);
    }

    .wrap {
      position: relative;
      max-width: 1100px;
      margin: 0 auto;
      padding: 2rem 1.25rem 3rem;
    }

    /* Header */
    .header {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-start;
      justify-content: space-between;
      gap: 1.25rem;
      margin-bottom: 2rem;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 1rem;
    }
    .logo {
      width: 2.75rem;
      height: 2.75rem;
      border-radius: 0.65rem;
      background: linear-gradient(135deg, #3b82f6, #1d4ed8);
      display: grid;
      place-items: center;
      box-shadow: var(--shadow-md);
      flex-shrink: 0;
    }
    .logo svg { width: 1.25rem; height: 1.25rem; fill: white; }
    .header h1 {
      margin: 0;
      font-size: 1.625rem;
      font-weight: 700;
      letter-spacing: -0.02em;
    }
    .header .subtitle {
      margin: 0.2rem 0 0;
      color: var(--muted-foreground);
      font-size: 0.9rem;
    }
    .header-links {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
    }
    .header-links a {
      display: inline-flex;
      align-items: center;
      gap: 0.35rem;
      padding: 0.45rem 0.85rem;
      font-size: 0.8125rem;
      font-weight: 500;
      color: var(--muted-foreground);
      text-decoration: none;
      border: 1px solid var(--border);
      border-radius: 0.5rem;
      background: var(--card);
      transition: color 0.15s, border-color 0.15s, box-shadow 0.15s;
    }
    .header-links a:hover {
      color: var(--foreground);
      border-color: var(--primary);
      box-shadow: var(--shadow-sm);
    }
    .header-links a svg {
      width: 1rem;
      height: 1rem;
      flex-shrink: 0;
      opacity: 0.85;
    }

    /* Stats */
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 1rem;
      margin-bottom: 1.5rem;
    }
    .stat-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 1.25rem 1.35rem;
      box-shadow: var(--shadow-sm);
      transition: box-shadow 0.2s, transform 0.2s;
    }
    .stat-card:hover {
      box-shadow: var(--shadow-md);
      transform: translateY(-2px);
    }
    .stat-card .stat-top {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 0.75rem;
    }
    .stat-icon {
      width: 2.25rem;
      height: 2.25rem;
      border-radius: 0.5rem;
      display: grid;
      place-items: center;
    }
    .stat-icon svg { width: 1.1rem; height: 1.1rem; }
    .stat-icon.blue { background: var(--primary-soft); color: var(--primary); }
    .stat-icon.green { background: var(--success-soft); color: var(--success); }
    .stat-label {
      font-size: 0.8125rem;
      font-weight: 500;
      color: var(--muted-foreground);
      margin: 0 0 0.15rem;
    }
    .stat-value {
      font-size: 1.75rem;
      font-weight: 700;
      letter-spacing: -0.03em;
      line-height: 1.1;
    }

    /* Alerts */
    .alerts { display: flex; flex-direction: column; gap: 0.65rem; margin-bottom: 1.5rem; }
    .alert {
      display: flex;
      gap: 0.75rem;
      padding: 0.9rem 1rem;
      border-radius: var(--radius);
      border: 1px solid;
      font-size: 0.875rem;
      box-shadow: var(--shadow-sm);
    }
    .alert-icon { flex-shrink: 0; margin-top: 0.1rem; }
    .alert-icon svg { width: 1.1rem; height: 1.1rem; }
    .alert-body strong { display: block; font-weight: 600; margin-bottom: 0.15rem; }
    .alert-body p { margin: 0; opacity: 0.9; }
    .alert.success { background: var(--success-soft); border-color: rgb(22 163 74 / 0.25); color: #166534; }
    @media (prefers-color-scheme: dark) {
      .alert.success { color: #86efac; border-color: rgb(34 197 94 / 0.3); }
    }
    .alert.error { background: var(--destructive-soft); border-color: rgb(220 38 38 / 0.25); color: #991b1b; }
    @media (prefers-color-scheme: dark) {
      .alert.error { color: #fca5a5; border-color: rgb(248 113 113 / 0.3); }
    }
    .alert.warning { background: var(--warning-soft); border-color: rgb(217 119 6 / 0.25); color: #92400e; }
    @media (prefers-color-scheme: dark) {
      .alert.warning { color: #fcd34d; border-color: rgb(251 191 36 / 0.3); }
    }
    .alert.info { background: var(--info-soft); border-color: rgb(37 99 235 / 0.2); color: #1e40af; }
    @media (prefers-color-scheme: dark) {
      .alert.info { color: #93c5fd; border-color: rgb(59 130 246 / 0.3); }
    }

    /* Layout */
    .layout {
      display: grid;
      grid-template-columns: 1fr;
      gap: 1.5rem;
    }
    @media (min-width: 900px) {
      .layout { grid-template-columns: 1fr 320px; align-items: start; }
    }

    .section-title {
      font-size: 1.05rem;
      font-weight: 600;
      margin: 0 0 1rem;
      letter-spacing: -0.01em;
    }

    /* Domain cards */
    .domain-list { display: flex; flex-direction: column; gap: 0.75rem; }
    .domain-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 1.15rem 1.25rem;
      box-shadow: var(--shadow-sm);
      transition: border-color 0.15s, box-shadow 0.2s;
    }
    .domain-card:hover {
      border-color: rgb(37 99 235 / 0.35);
      box-shadow: var(--shadow-md);
    }
    .domain-card-head {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 0.5rem;
      margin-bottom: 0.65rem;
    }
    .domain-name {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 1rem;
      font-weight: 600;
      color: var(--primary);
      text-decoration: none;
    }
    .domain-name:hover { text-decoration: underline; }
    .domain-name svg { width: 1rem; height: 1rem; opacity: 0.7; }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 0.35rem;
      padding: 0.2rem 0.55rem;
      font-size: 0.6875rem;
      font-weight: 600;
      border-radius: 9999px;
      border: 1px solid transparent;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .badge.online {
      background: var(--success-soft);
      color: var(--success);
      border-color: rgb(22 163 74 / 0.2);
    }
    .badge.offline {
      background: var(--border);
      color: var(--muted);
    }
    .badge.stale {
      background: var(--warning-soft);
      color: var(--warning);
      border-color: rgb(217 119 6 / 0.25);
    }
    .badge-dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: currentColor;
    }
    .badge.online .badge-dot { box-shadow: 0 0 0 2px rgb(22 163 74 / 0.25); }

    .tunnel-block {
      padding: 0.75rem 0.9rem;
      background: var(--background);
      border: 1px solid var(--border);
      border-radius: 0.5rem;
      margin-bottom: 0.85rem;
      font-size: 0.8125rem;
    }
    .tunnel-block .label {
      color: var(--muted-foreground);
      font-size: 0.75rem;
      margin-bottom: 0.25rem;
    }
    .tunnel-block a {
      color: var(--primary);
      word-break: break-all;
      font-weight: 500;
    }
    .tunnel-block .empty { color: var(--muted-foreground); font-style: italic; }

    .card-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
    }
    .card-actions form { display: inline; margin: 0; }

    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 0.35rem;
      padding: 0.45rem 0.9rem;
      font-size: 0.8125rem;
      font-weight: 500;
      font-family: inherit;
      border-radius: 0.5rem;
      border: 1px solid transparent;
      cursor: pointer;
      transition: background 0.15s, color 0.15s, border-color 0.15s, box-shadow 0.15s;
    }
    .btn-primary {
      background: var(--primary);
      color: var(--primary-foreground);
      box-shadow: var(--shadow-sm);
    }
    .btn-primary:hover { filter: brightness(1.08); }
    .btn-outline {
      background: var(--card);
      color: var(--foreground);
      border-color: var(--border);
    }
    .btn-outline:hover {
      background: var(--background);
      border-color: var(--muted);
    }
    .btn-ghost {
      background: transparent;
      color: var(--muted-foreground);
      border-color: var(--border);
    }
    .btn-ghost:hover {
      color: var(--destructive);
      border-color: rgb(220 38 38 / 0.35);
      background: var(--destructive-soft);
    }

    /* Empty state */
    .empty-state {
      text-align: center;
      padding: 2.5rem 1.5rem;
      background: var(--card);
      border: 1px dashed var(--border);
      border-radius: var(--radius);
    }
    .empty-state svg {
      width: 2.5rem;
      height: 2.5rem;
      color: var(--muted);
      margin-bottom: 0.75rem;
    }
    .empty-state h3 { margin: 0 0 0.35rem; font-size: 1rem; }
    .empty-state p { margin: 0; color: var(--muted-foreground); font-size: 0.875rem; }

    /* Add domain panel */
    .add-panel {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 1.35rem;
      box-shadow: var(--shadow-sm);
      position: sticky;
      top: 1.25rem;
    }
    .add-panel p.hint {
      margin: 0 0 1.1rem;
      font-size: 0.8125rem;
      color: var(--muted-foreground);
      line-height: 1.45;
    }
    .field { margin-bottom: 1rem; }
    .field label {
      display: block;
      font-size: 0.8125rem;
      font-weight: 500;
      margin-bottom: 0.4rem;
      color: var(--foreground);
    }
    .input-wrap {
      display: flex;
      align-items: stretch;
      border: 1px solid var(--input);
      border-radius: 0.5rem;
      overflow: hidden;
      background: var(--background);
      transition: border-color 0.15s, box-shadow 0.15s;
    }
    .input-wrap:focus-within {
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgb(37 99 235 / 0.15);
    }
    .input-wrap input {
      flex: 1;
      min-width: 0;
      border: none;
      background: transparent;
      padding: 0.6rem 0.75rem;
      font-size: 0.9rem;
      font-family: inherit;
      color: var(--foreground);
      outline: none;
    }
    .input-suffix {
      display: flex;
      align-items: center;
      padding: 0 0.75rem;
      font-size: 0.8125rem;
      font-weight: 500;
      color: var(--muted-foreground);
      background: var(--border);
      border-left: 1px solid var(--input);
    }
    .btn-block {
      width: 100%;
      padding: 0.65rem 1rem;
      font-size: 0.9rem;
    }

    code {
      font-size: 0.85em;
      padding: 0.1em 0.35em;
      border-radius: 0.25rem;
      background: var(--border);
    }
  </style>
</head>
<body>
  <div class="page-bg" aria-hidden="true"></div>
  <div class="wrap">
    <header class="header">
      <div class="brand">
        <div class="logo" aria-hidden="true">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 2L2 7v10l10 5 10-5V7L12 2zm0 2.2l7.5 3.75v7.5L12 19.3 4.5 15.45v-7.5L12 4.2z"/></svg>
        </div>
        <div>
          <h1>WSLWebStack</h1>
          <p class="subtitle">Панель локальных доменов для разработки в WSL2</p>
        </div>
      </div>
      <nav class="header-links" aria-label="Быстрые ссылки">
        <a href="https://localhost/phpmyadmin" target="_blank" rel="noopener">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.66 4.03 3 9 3s9-1.34 9-3V5"/><path d="M3 12c0 1.66 4.03 3 9 3s9-1.34 9-3"/></svg>
          phpMyAdmin
        </a>
        <a href="http://127.0.0.1:15672/" target="_blank" rel="noopener">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.59 13.51 6.83 3.98"/><path d="M15.41 6.51l-6.82 3.98"/></svg>
          RabbitMQ
        </a>
      </nav>
    </header>

    <div class="stats">
      <div class="stat-card">
        <div class="stat-top">
          <div class="stat-icon blue" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
          </div>
        </div>
        <p class="stat-label">Зарегистрировано доменов</p>
        <p class="stat-value"><?= (int) $domainCount ?></p>
      </div>
      <div class="stat-card">
        <div class="stat-top">
          <div class="stat-icon green" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
          </div>
        </div>
        <p class="stat-label">Активных туннелей</p>
        <p class="stat-value"><?= (int) $activeTunnelCount ?></p>
      </div>
    </div>

    <?php if ($ok || $error || $tunnelFlash): ?>
    <div class="alerts" role="status">
      <?php if ($ok): ?>
      <div class="alert success" role="alert">
        <span class="alert-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg></span>
        <div class="alert-body"><strong>Готово</strong><p><?= h($ok) ?></p></div>
      </div>
      <?php endif; ?>
      <?php if ($error): ?>
      <div class="alert error" role="alert">
        <span class="alert-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg></span>
        <div class="alert-body"><strong>Ошибка</strong><p><?= h($error) ?></p></div>
      </div>
      <?php endif; ?>
      <?php if ($tunnelFlash): ?>
      <div class="alert success" role="alert">
        <span class="alert-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg></span>
        <div class="alert-body"><strong>Туннель</strong><p><?= nl2br(h($tunnelFlash)) ?></p></div>
      </div>
      <?php endif; ?>
    </div>
    <?php endif; ?>

    <div class="alert warning" role="alert" style="margin-bottom:1.5rem">
      <span class="alert-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg></span>
      <div class="alert-body">
        <strong>Публичный доступ через Quick Tunnel</strong>
        <p>Пока туннель включён, сайт доступен из интернета по ссылке <code>*.trycloudflare.com</code>. URL меняется после перезапуска. Не публикуйте то, что не готовы показать третьим лицам.</p>
      </div>
    </div>

    <div class="alert info" role="note" style="margin-bottom:1.5rem">
      <span class="alert-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg></span>
      <div class="alert-body">
        <strong>Cloudflare Quick Tunnel</strong>
        <p>Для постоянного URL нужен named tunnel в аккаунте Cloudflare. Quick Tunnel выдаёт временный адрес при каждом запуске.</p>
      </div>
    </div>

    <div class="layout">
      <section aria-labelledby="domains-heading">
        <h2 class="section-title" id="domains-heading">Домены</h2>

        <?php if ($domainRows === []): ?>
        <div class="empty-state">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M12 2L2 7v10l10 5 10-5V7L12 2z"/><path d="M12 22V12"/><path d="M2 7l10 5 10-5"/><path d="M12 12 22 7"/></svg>
          <h3>Пока нет доменов</h3>
          <p>Добавьте первый домен в форме справа — появится сайт <code>имя.local</code></p>
        </div>
        <?php else: ?>
        <div class="domain-list">
          <?php foreach ($domainRows as $row):
              $domain = $row['domain'];
              $t = $row['tunnel'];
              if ($t['active'] && $t['url'] !== '') {
                  $badgeClass = 'online';
                  $badgeLabel = 'Туннель активен';
              } elseif ($t['url'] !== '') {
                  $badgeClass = 'stale';
                  $badgeLabel = 'URL устарел';
              } else {
                  $badgeClass = 'offline';
                  $badgeLabel = 'Локально';
              }
          ?>
          <article class="domain-card">
            <div class="domain-card-head">
              <a class="domain-name" href="https://<?= h($domain) ?>/" target="_blank" rel="noopener">
                <?= h($domain) ?>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>
              </a>
              <span class="badge <?= h($badgeClass) ?>">
                <span class="badge-dot" aria-hidden="true"></span>
                <?= h($badgeLabel) ?>
              </span>
            </div>

            <div class="tunnel-block">
              <div class="label">Публичный URL</div>
              <?php if ($t['url'] !== ''): ?>
                <a href="<?= h($t['url']) ?>" target="_blank" rel="noopener"><?= h($t['url']) ?></a>
                <?php if (!$t['active']): ?>
                  <span style="display:block;margin-top:0.35rem;color:var(--warning);font-size:0.75rem">Туннель остановлен — ссылка может не работать</span>
                <?php endif; ?>
              <?php else: ?>
                <span class="empty">Туннель не запущен</span>
              <?php endif; ?>
            </div>

            <div class="card-actions">
              <?php if ($t['active']): ?>
              <form method="post" action="/tunnel-action.php">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="domain" value="<?= h($domain) ?>">
                <input type="hidden" name="do" value="stop">
                <button type="submit" class="btn btn-ghost">Остановить туннель</button>
              </form>
              <?php else: ?>
              <form method="post" action="/tunnel-action.php">
                <input type="hidden" name="csrf" value="<?= h($csrf) ?>">
                <input type="hidden" name="domain" value="<?= h($domain) ?>">
                <input type="hidden" name="do" value="start">
                <button type="submit" class="btn btn-primary">Запустить туннель</button>
              </form>
              <?php endif; ?>
            </div>
          </article>
          <?php endforeach; ?>
        </div>
        <?php endif; ?>
      </section>

      <aside class="add-panel" aria-labelledby="add-heading">
        <h2 class="section-title" id="add-heading" style="margin-top:0">Новый домен</h2>
        <p class="hint">Создаёт vhost Apache, каталог в <code>/var/www/</code> и самоподписанный HTTPS-сертификат. На Windows может понадобиться <code>sync-hosts.ps1</code>.</p>
        <form method="post" action="/add-domain.php">
          <div class="field">
            <label for="domain-name">Имя (без .local)</label>
            <div class="input-wrap">
              <input id="domain-name" name="name" required pattern="[a-z0-9-]{2,31}" placeholder="shopium" autocomplete="off" spellcheck="false">
              <span class="input-suffix">.local</span>
            </div>
          </div>
          <button type="submit" class="btn btn-primary btn-block">Добавить домен</button>
        </form>
      </aside>
    </div>
  </div>
</body>
</html>
