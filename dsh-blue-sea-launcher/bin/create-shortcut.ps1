# ============================================================================
# create-shortcut.ps1 —— 手动生成「蓝海之约」桌面快捷方式(不依赖 dsh 重启)
# 双击 bin/create-shortcut.cmd 即可;或直接:
#   powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcut.ps1
# ============================================================================
param(
  [string]$Name = '蓝海之约',
  [string]$Url = 'http://127.0.0.1:3080',
  [int]$Port = 3080
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$binDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$target = Join-Path $binDir 'launch.cmd'
$icon = Join-Path (Split-Path -Parent $binDir) 'assets\whale-icon.ico'
$workdir = Split-Path -Parent $binDir

if (-not (Test-Path $target)) { Write-Host "找不到启动器: $target" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $icon)) { $icon = $target }

# 候选位置: 桌面 → 开始菜单 → 用户主目录
$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
$programs = [Environment]::GetFolderPath('Programs')
$homeDir = $env:USERPROFILE

$candidates = @($desktop, $programs, $homeDir) | Where-Object { $_ -and (Test-Path $_) }

$ws = New-Object -ComObject WScript.Shell
$args_ = "$Url $Port"
$created = $null
$first = $true

foreach ($dir in $candidates) {
  $lnk = Join-Path $dir ($Name + '.lnk')
  try {
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $target
    $s.Arguments = $args_
    $s.WorkingDirectory = $workdir
    $s.IconLocation = ($icon + ',0')
    $s.Description = "$Name - DeepSeek Harness"
    $s.WindowStyle = 1
    $s.Save()
    if (Test-Path $lnk) {
      $where = if ($first) { '桌面' } elseif ($dir -eq $programs) { '开始菜单' } else { '用户主目录' }
      Write-Host "已创建快捷方式($where): $lnk" -ForegroundColor Green
      $created = $lnk
      if ($first) { break }   # 桌面成功即完成;否则继续尝试其余位置
      break
    }
  } catch {
    Write-Host "此位置创建失败: $dir — $($_.Exception.Message)" -ForegroundColor Yellow
  }
  $first = $false
}

if (-not $created) {
  Write-Host '所有位置都创建失败。可能被安全软件/组策略拦截，请尝试手动: 右键 launch.cmd → 发送到 → 桌面快捷方式' -ForegroundColor Red
  exit 2
}
exit 0
