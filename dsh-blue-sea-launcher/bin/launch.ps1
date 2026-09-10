# ============================================================================
# 蓝海之约 launcher (dsh-blue-sea-launcher)
# ----------------------------------------------------------------------------
# 打开 DeepSeek Harness Web。v0.1.4 —— 自适应 dsh 版本变化:
#   1. 宽匹配启动地址: 不再依赖固定日志格式,从服务输出里抓取「最后一个 http 地址」,
#      优先带 token/?t= 参数的地址(新版 dsh),没有也能用裸地址(旧版 dsh)。
#   2. 打开前先访问验证: 只有地址真正可进入(200/302)才交给浏览器;收到 401/错误
#      就继续等待并重试 —— 因此 dsh 改版导致登录方式变化时不会"第一次打开失败"。
#   3. 任何一步失败都退化为"打开裸地址",并在控制台给出提示,不静默失效。
#   其余保持: --no-open、单实例互斥、端口检活、日志重定向到 <DSH_HOME>/dsh-web-url.log
#
# 用法: launch.ps1 [-DryRun] [url] [port]
# ============================================================================
param(
  [string]$Url = 'http://127.0.0.1:3080',
  [int]$Port = 3080,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$urlLog = Join-Path $dshHome 'dsh-web-url.log'

function Test-PortOpen([string]$hostOrIp, [int]$p) {
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $r = $c.BeginConnect($hostOrIp, $p, $null, $null)
    $ok = $r.AsyncWaitHandle.WaitOne(1000) -and $c.Connected
    if ($ok) { $c.EndConnect($r) }
    $c.Close()
    return $ok
  } catch {
    return $false
  }
}

function Test-ServerUp([int]$p) {
  return (Test-PortOpen '127.0.0.1' $p) -or (Test-PortOpen '::1' $p)
}

function Read-ServerUrl {
  # 宽匹配: 抓服务输出里的所有 http 地址,优先带 token/?t= 的(新版 dsh),否则取最后一个
  if (-not (Test-Path $urlLog)) { return $null }
  try {
    $text = Get-Content $urlLog -Raw -ErrorAction Stop
    $all = [regex]::Matches($text, 'https?://[^\s"'']+') | ForEach-Object { $_.Value.TrimEnd('.', ',', ')', '）') }
    if ($all.Count -eq 0) { return $null }
    $token = $all | Where-Object { $_ -match '[?&](token|t)=' } | Select-Object -Last 1
    $picked = if ($token) { $token } else { $all[$all.Count - 1] }
    $t = (Get-Item $urlLog).LastWriteTime
    if (((Get-Date) - $t).TotalMinutes -lt 30) { return $picked }
  } catch { }
  return $null
}

function Test-UrlReady([string]$u) {
  # 只有真正能进入(200/302/303)才算就绪;401(需要登录)视为未就绪
  try {
    $resp = Invoke-WebRequest -Uri $u -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 6 -ErrorAction Stop
    return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
  } catch {
    $code = $null
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code -ge 200 -and $code -lt 400) { return $true }
    return $false
  }
}

# ---- single-instance guard ----
$mutex = $null
try {
  $mutex = New-Object System.Threading.Mutex($false, 'BlueSeaLauncher_DSH')
  try {
    if (-not $mutex.WaitOne(0)) {
      Write-Output 'busy: another launcher is already working'
      exit 7
    }
  } catch [System.Threading.AbandonedMutexException] {
  }
} catch {
  $mutex = $null
}

try {
  if (Test-ServerUp $Port) {
    $serverUrl = Read-ServerUrl
    $target = if ($serverUrl) { $serverUrl } else { $Url }
    Write-Output ('dsh web is already running — opening ' + $target)
    if (-not $DryRun) { Start-Process $target }
    exit 0
  }

  Write-Output ('dsh web is not running — starting server (--no-open)...')
  if (-not $DryRun) {
    if (Test-Path $urlLog) { Remove-Item $urlLog -Force }
    $npx = Join-Path $env:SystemDrive 'node\npx.cmd'
    if (-not (Test-Path $npx)) { $npx = 'npx.cmd' }
    $errLog = $urlLog + '.err'
    Start-Process -FilePath $npx -ArgumentList '--verbose', '@deepseek-ai/dsh', 'web', '--no-open' `
      -RedirectStandardOutput $urlLog -RedirectStandardError $errLog -WindowStyle Minimized
  } else {
    Write-Output 'dry-run: would run: npx --verbose @deepseek-ai/dsh web --no-open'
    Write-Output ('dry-run: would poll ' + $urlLog + ' and verify the URL before opening')
    exit 0
  }

  # 轮询: 抓到地址 → 验证可进入 → 打开;dsh 改版导致地址格式变化也能自适应
  $deadline = (Get-Date).AddSeconds(60)
  $lastTried = $null
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $serverUrl = Read-ServerUrl
    if ($serverUrl -and $serverUrl -ne $lastTried) {
      $lastTried = $serverUrl
      if (Test-UrlReady $serverUrl) {
        Write-Output ('verified reachable — opening ' + $serverUrl)
        if (-not $DryRun) { Start-Process $serverUrl }
        exit 0
      }
    } elseif ($serverUrl -and (Test-UrlReady $serverUrl)) {
      Write-Output ('verified reachable — opening ' + $serverUrl)
      if (-not $DryRun) { Start-Process $serverUrl }
      exit 0
    }
  }

  # 超时兜底: 端口通了就打开(即使未能验证),并提示
  $serverUrl = Read-ServerUrl
  if ($serverUrl) {
    Write-Output ('could not verify but opening anyway: ' + $serverUrl)
    if (-not $DryRun) { Start-Process $serverUrl }
    exit 0
  }
  if (Test-ServerUp $Port) {
    Write-Output ('server is up but no URL captured — opening ' + $Url)
    if (-not $DryRun) { Start-Process $Url }
    exit 0
  }

  Write-Output 'server did not become ready in 60s — start it manually: npx --verbose @deepseek-ai/dsh web'
  exit 1
} finally {
  if ($mutex) {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
  }
}
