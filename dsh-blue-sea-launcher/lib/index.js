// ============================================================================
// dsh-blue-sea-launcher —— 宿主侧插件本体
// ----------------------------------------------------------------------------
// 装载时（DSH web profile 启动后）确保存在「蓝海之约」快捷方式：
//   1. 目标   : <插件目录>/bin/launch.cmd
//   2. 参数   : url port（来自 config，默认 http://127.0.0.1:3080 3080）
//   3. 图标   : <插件目录>/assets/whale-icon.ico
//   位置优先级: 桌面 → 开始菜单 → 用户主目录（任一处成功即可，逐级兜底）
//   结果写入 <DSH_HOME>/dsh-blue-sea-launcher-status.log，便于用户反馈排查。
//
// 失败排查要点（v0.1.5 起会明确打印）：
//   - 非 Windows 平台：没有"桌面快捷方式"概念，插件只记录状态不报错
//   - 装完未重启 dsh web：bundle 只在启动时组合，插件不会运行（常见原因）
//   - 或直接双击 <插件目录>/bin/create-shortcut.cmd 手动创建（无需重启）
// ============================================================================

import { spawn } from 'node:child_process'
import { appendFileSync, existsSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Package root: lib/index.js -> package root. Keeps the bundle relocatable
// whether installed as a normal npm plugin (node_modules) or a local link.
const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

const name = 'blue-sea-launcher'
const inject = []

const DEFAULT_CONFIG = {
  shortcutName: '蓝海之约',
  url: 'http://127.0.0.1:3080',
  port: 3080,
  launcher: 'bin/launch.cmd',
  icon: 'assets/whale-icon.ico',
}

// PowerShell：输入全部通过 DSH_BS_* 环境变量传递；依次尝试 桌面 → 开始菜单 → 主目录。
// 输出一行结果：CREATED <path> / UP_TO_DATE <path> / FALLBACK <path> / FAILED <reason>
const SHORTCUT_PS = `
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'
$name      = $env:DSH_BS_NAME
$target    = $env:DSH_BS_TARGET
$arguments = $env:DSH_BS_ARGS
$icon      = $env:DSH_BS_ICON
$workdir   = $env:DSH_BS_WORKDIR
$desc      = $env:DSH_BS_DESC

$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
$programs = [Environment]::GetFolderPath('Programs')
$homeDir = $env:USERPROFILE

$dirs = @()
foreach ($d in @($desktop, $programs, $homeDir)) { if ($d -and (Test-Path $d)) { $dirs += $d } }
if (-not $dirs.Count) { Write-Output 'FAILED no-writable-location'; exit 3 }

try { $ws = New-Object -ComObject WScript.Shell } catch { Write-Output ('FAILED com:' + $_.Exception.Message); exit 3 }

$idx = 0
foreach ($dir in $dirs) {
  $lnk = Join-Path $dir ($name + '.lnk')
  try {
    if (Test-Path $lnk) {
      $old = $ws.CreateShortcut($lnk)
      if ($old.TargetPath -eq $target -and $old.Arguments -eq $arguments -and $old.IconLocation -eq ($icon + ',0')) {
        Write-Output ('UP_TO_DATE ' + $lnk)
        exit 0
      }
    }
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $target
    $s.Arguments = $arguments
    $s.WorkingDirectory = $workdir
    $s.IconLocation = ($icon + ',0')
    $s.Description = $desc
    $s.WindowStyle = 1
    $s.Save()
    if (Test-Path $lnk) {
      if ($idx -eq 0) { Write-Output ('CREATED ' + $lnk) } else { Write-Output ('FALLBACK ' + $lnk) }
      exit 0
    }
  } catch {
    $lastErr = $_.Exception.Message
  }
  $idx++
}
Write-Output ('FAILED ' + ($lastErr -replace '\\s+', ' '))
exit 3
`

function runShortcutScript(cfg, launcherPath, iconPath) {
  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-Command', SHORTCUT_PS,
    ], {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: {
        ...process.env,
        DSH_BS_NAME: String(cfg.shortcutName),
        DSH_BS_TARGET: launcherPath,
        DSH_BS_ARGS: `${cfg.url} ${cfg.port}`,
        DSH_BS_ICON: iconPath,
        DSH_BS_WORKDIR: PACKAGE_ROOT,
        DSH_BS_DESC: `${cfg.shortcutName} - DeepSeek Harness`,
      },
    })
    let out = ''
    let err = ''
    child.stdout.on('data', (d) => { out += d })
    child.stderr.on('data', (d) => { err += d })
    child.on('error', reject)
    child.on('close', (code) => {
      const line = out.trim().split('\n').pop() || ''
      if (line.startsWith('CREATED') || line.startsWith('UP_TO_DATE') || line.startsWith('FALLBACK')) resolve(line)
      else reject(new Error(line || err.trim() || `powershell exit ${code}`))
    })
  })
}

function writeStatus(entry) {
  try {
    const home = process.env.DSH_HOME || path.join(os.homedir(), '.dsh')
    const file = path.join(home, 'dsh-blue-sea-launcher-status.log')
    appendFileSync(file, `[${new Date().toISOString()}] ${entry}\n`, 'utf8')
    return file
  } catch (e) {
    return null
  }
}

function apply(ctx, config = {}) {
  const cfg = { ...DEFAULT_CONFIG, ...config }
  const launcherPath = path.join(PACKAGE_ROOT, cfg.launcher)
  const iconPath = path.join(PACKAGE_ROOT, cfg.icon)
  const log = ctx.logger ? ctx.logger('blue-sea-launcher') : console

  async function ensureShortcut() {
    // 非 Windows：没有桌面快捷方式概念，明确记录，不视为错误
    if (process.platform !== 'win32') {
      const msg = `skip: platform=${process.platform} (desktop shortcut requires Windows)`
      log.warn(msg)
      writeStatus(msg)
      return
    }
    if (!existsSync(launcherPath)) {
      const msg = `launcher script missing: ${launcherPath} — run bin/create-shortcut.cmd after reinstalling`
      log.warn(msg)
      writeStatus(msg)
      return
    }
    if (!existsSync(iconPath)) {
      log.warn(`icon file missing: ${iconPath} — shortcut still created without the icon`)
    }
    try {
      const line = await runShortcutScript(cfg, launcherPath, existsSync(iconPath) ? iconPath : launcherPath)
      if (line.startsWith('UP_TO_DATE')) log.info(`shortcut up to date: ${line.slice('UP_TO_DATE '.length)}`)
      else if (line.startsWith('FALLBACK')) log.info(`desktop unavailable — shortcut created at: ${line.slice('FALLBACK '.length)} (manual: bin/create-shortcut.cmd)`)
      else log.info(`shortcut created: ${line.slice('CREATED '.length)}`)
      writeStatus(`ok: ${line}`)
    } catch (err) {
      const msg = String((err && err.message) || err)
      log.error(`shortcut creation failed: ${msg}`)
      log.error(`manual fallback: double-click ${path.join(PACKAGE_ROOT, 'bin', 'create-shortcut.cmd')}`)
      writeStatus(`failed: ${msg}`)
    }
  }

  // Defer one tick so a slow COM call never blocks the boot tree.
  const timer = setTimeout(() => { void ensureShortcut() }, 500)
  ctx.effect(() => () => clearTimeout(timer))
}

export { name, inject, apply }
