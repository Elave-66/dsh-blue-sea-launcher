# ============================================================================
# 蓝海之约 launcher (dsh-blue-sea-launcher)
# ----------------------------------------------------------------------------
# 打开 DeepSeek Harness Web。v0.1.2 适配新版本 dsh web 的 token 登录:
#   新版本 dsh web 启动时打印「dsh web: <带 ?t=token 的 URL>」,浏览器必须先
#   访问该 URL 换取签名 Cookie 之后才能进入主页面。裸地址直接访问会收到 401。
#   因此本版本:
#     - 启动服务器时把输出重定向到 <DSH_HOME>/dsh-web-url.log(实际上被 DSH_HOME 下)
#     - 轮询日志中的 token URL 后,用该 URL 打开浏览器(保证登录成功)
#     - 服务已在运行时:若日志里有本次进程的 token URL 则用其打开,否则打开裸地址
#     - 其余保持 v0.1.1: --no-open、端口就绪轮询、单实例互斥、127.0.0.1/::1 检活
#
# 用法: launch.ps1 [-DryRun] [url] [port]
#   -DryRun     只打印将要执行的动作,不真正启动服务器/浏览器(内部测试用)
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

function Read-TokenUrl {
  # 从日志中提取最新的「dsh web: <url>」行;只在日志最后写入时间足够新时返回
  if (-not (Test-Path $urlLog)) { return $null }
  try {
    foreach ($line in @(Get-Content $urlLog -ErrorAction Stop)) {
      if ($line -match 'dsh web:\s*(https?://\S+)') { $match = $matches[1] }
    }
    $t = (Get-Item $urlLog).LastWriteTime
    if ($match -and ((Get-Date) - $t).TotalMinutes -lt 30) { return $match }
  } catch { }
  return $null
}

# ---- single-instance guard: another launcher already working -> exit quietly ----
$mutex = $null
try {
  $mutex = New-Object System.Threading.Mutex($false, 'BlueSeaLauncher_DSH')
  try {
    if (-not $mutex.WaitOne(0)) {
      Write-Output 'busy: another launcher is already working'
      exit 7
    }
  } catch [System.Threading.AbandonedMutexException] {
    # previous run was killed mid-flight; the mutex is ours now — proceed
  }
} catch {
  $mutex = $null  # mutex unavailable (very rare) — proceed without the guard
}

try {
  if (Test-ServerUp $Port) {
    $tokenUrl = Read-TokenUrl
    if ($tokenUrl) {
      Write-Output ('dsh web is already running — opening tokenized URL ' + $tokenUrl)
      if (-not $DryRun) { Start-Process $tokenUrl }
    } else {
      Write-Output ('dsh web is already running at ' + $Url + ' — opening browser')
      if (-not $DryRun) { Start-Process $Url }
    }
    exit 0
  }

  Write-Output ('dsh web is not running — starting server (--no-open)...')
  if (-not $DryRun) {
    # 覆盖旧日志,避免读到上一进程的失效 token
    if (Test-Path $urlLog) { Remove-Item $urlLog -Force }
    $npx = Join-Path $env:SystemDrive 'node\npx.cmd'
    if (-not (Test-Path $npx)) { $npx = 'npx.cmd' }
    $errLog = $urlLog + '.err'
    Start-Process -FilePath $npx -ArgumentList '--verbose', '@deepseek-ai/dsh', 'web', '--no-open' `
      -RedirectStandardOutput $urlLog -RedirectStandardError $errLog -WindowStyle Minimized
  } else {
    Write-Output 'dry-run: would run: npx --verbose @deepseek-ai/dsh web --no-open'
    Write-Output ('dry-run: would wait for port ' + $Port + ' then open token URL from ' + $urlLog)
    exit 0
  }

  # 真正的"就绪信号"是日志里的 token 地址行(端口打开≠认证服务就绪)。
  # 只在 token 地址出现后打开浏览器,否则第一次访问会撞上未就绪的认证层 → 英文错误页。
  $deadline = (Get-Date).AddSeconds(45)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 400
    $tokenUrl = Read-TokenUrl
    if ($tokenUrl) {
      Start-Sleep -Milliseconds 600   # 认证服务与静态资源完全就绪的缓冲
      Write-Output ('token URL ready — opening ' + $tokenUrl)
      if (-not $DryRun) { Start-Process $tokenUrl }
      exit 0
    }
  }
  # 兜底: 端口通了但 45 秒内没等到 token 行(服务启动异常/日志被别处占用)
  if (Test-ServerUp $Port) {
    Write-Output ('server is up but no token URL found — opening ' + $Url)
    if (-not $DryRun) { Start-Process $Url }
    exit 0
  }

  Write-Output 'server did not become ready in 45s — start it manually: npx --verbose @deepseek-ai/dsh web'
  exit 1
} finally {
  if ($mutex) {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
  }
}
