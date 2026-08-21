// ============================================================================
// dsh-blue-sea-launcher —— 宿主侧插件本体
// ----------------------------------------------------------------------------
// 装载时（DSH web profile 启动后）确保桌面存在「蓝海之约」快捷方式：
//   1. 目标   : <插件目录>/bin/launch.cmd
//   2. 参数   : url port（来自 config，默认 http://127.0.0.1:3080 3080）
//   3. 图标   : <插件目录>/assets/whale-icon.ico（直接取自打包内的 ico）
// 点击快捷方式后 launch.cmd 会：
//   - 若 127.0.0.1:port 已有 DSH web 在监听 -> 直接打开浏览器
//   - 否则启动 `npx --verbose @deepseek-ai/dsh web` 再打开浏览器
//
// 快捷方式已存在且目标/图标一致时插件不重复写入（不刷新时间戳）。
// 卸载插件不会删除已经创建的快捷方式（它先于 DSH 启动，是"入口"）。
// ============================================================================

import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Package root: lib/index.js -> package root. Keeps the bundle relocatable
// whether installed as a normal npm plugin (node_modules) or a local link.
const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

// Executable name: the service name registered in the boot tree.
const name = 'blue-sea-launcher'

// No service dependencies: everything we need is node: builtins + COM via
// powershell.exe. Empty inject list keeps the entry trivial to mount.
const inject = []

const DEFAULT_CONFIG = {
  shortcutName: '蓝海之约',
  url: 'http://127.0.0.1:3080',
  port: 3080,
  launcher: 'bin/launch.cmd',
  icon: 'assets/whale-icon.ico',
}

// PowerShell script: reads all inputs from DSH_BS_* environment variables
// (spawn env), so nothing needs quoting through the command line. Values are
// picked up either as a shortcut mapping or via `.lnk` recreation.
const SHORTCUT_PS = `
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$name       = $env:DSH_BS_NAME
$target     = $env:DSH_BS_TARGET
$arguments  = $env:DSH_BS_ARGS
$icon       = $env:DSH_BS_ICON
$workdir    = $env:DSH_BS_WORKDIR
$desc       = $env:DSH_BS_DESC
$desktop    = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
$lnk = Join-Path $desktop ($name + '.lnk')
$ws = New-Object -ComObject WScript.Shell
if (Test-Path $lnk) {
  $old = $ws.CreateShortcut($lnk)
  if ($old.TargetPath -eq $target -and $old.Arguments -eq $arguments -and $old.IconLocation -eq ($icon + ',0')) {
    Write-Output ('UP_TO_DATE ' + $lnk)
    exit 0
  }
}
$s = $ws.CreateShortcut($lnk)
$s.TargetPath    = $target
$s.Arguments     = $arguments
$s.WorkingDirectory = $workdir
$s.IconLocation  = ($icon + ',0')
$s.Description   = $desc
$s.WindowStyle   = 1
$s.Save()
Write-Output ('CREATED ' + $lnk)
`

/** Run the shortcut PS script; resolves to its stdout (trimmed). */
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
      if (code === 0) resolve(out.trim())
      else reject(new Error(`powershell exit ${code}: ${err.trim() || out.trim()}`))
    })
  })
}

function apply(ctx, config = {}) {
  const cfg = { ...DEFAULT_CONFIG, ...config }
  const launcherPath = path.join(PACKAGE_ROOT, cfg.launcher)
  const iconPath = path.join(PACKAGE_ROOT, cfg.icon)
  const log = ctx.logger ? ctx.logger('blue-sea-launcher') : console

  async function ensureShortcut() {
    if (!existsSync(launcherPath)) {
      log.warn(`launcher script missing: ${launcherPath} — skip shortcut creation`)
      return
    }
    if (!existsSync(iconPath)) {
      log.warn(`icon file missing: ${iconPath} — skip shortcut creation`)
      return
    }
    try {
      const line = await runShortcutScript(cfg, launcherPath, iconPath)
      if (line.startsWith('UP_TO_DATE')) {
        log.info(`shortcut up to date: ${line.slice('UP_TO_DATE '.length)}`)
      } else {
        log.info(`desktop shortcut created: ${line}`)
        log.info(`target: ${launcherPath} ${cfg.url} ${cfg.port}`)
        log.info(`icon: ${iconPath}`)
      }
    } catch (err) {
      log.error(`shortcut creation failed: ${String((err && err.message) || err)}`)
    }
  }

  // Defer one tick so a slow COM call never blocks the boot tree.
  const timer = setTimeout(() => { void ensureShortcut() }, 500)
  ctx.effect(() => () => clearTimeout(timer))
}

export { name, inject, apply }
