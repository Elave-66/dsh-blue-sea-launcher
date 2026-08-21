# ============================================================================
# 蓝海之约 launcher (dsh-blue-sea-launcher)
# ----------------------------------------------------------------------------
# 打开 DeepSeek Harness Web。相比 v0.1.0 的修复:
#   1. 启动服务器时传 --no-open —— dsh web 默认会自己打开浏览器(openBrowser),
#      与启动器的打开动作叠加就是"开了两次"。现在只由本启动器打开一次。
#   2. 不再固定等待 4 秒,而是轮询直到端口真正就绪(最多 30 秒)再打开。
#   3. 单实例互斥锁: 双击/重复点击时,后到的实例直接退出,不会重复启动或重复打开。
#   4. 检活同时探测 127.0.0.1 与 ::1。
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
    Write-Output ('dsh web is already running at ' + $Url + ' — opening browser')
    if (-not $DryRun) { Start-Process $Url }
    exit 0
  }

  Write-Output ('dsh web is not running — starting server (--no-open)...')
  if (-not $DryRun) {
    $npx = Join-Path $env:SystemDrive 'node\npx.cmd'
    if (-not (Test-Path $npx)) { $npx = 'npx.cmd' }
    Start-Process -FilePath $npx -ArgumentList '--verbose', '@deepseek-ai/dsh', 'web', '--no-open' -WindowStyle Minimized
  } else {
    Write-Output 'dry-run: would run: npx --verbose @deepseek-ai/dsh web --no-open'
    Write-Output ('dry-run: would wait for port ' + $Port + ' then open ' + $Url)
    exit 0
  }

  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if (Test-ServerUp $Port) {
      Write-Output ('server is up at ' + $Url + ' — opening browser')
      Start-Process $Url
      exit 0
    }
  }

  Write-Output 'server did not become ready in 30s — start it manually: npx --verbose @deepseek-ai/dsh web'
  exit 1
} finally {
  if ($mutex) {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
  }
}
