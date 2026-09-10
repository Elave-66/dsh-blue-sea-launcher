# 蓝海之约启动器（dsh-blue-sea-launcher）

DeepSeek Harness（DSH）bundle 插件：**装载到 web profile 后**，自动在桌面生成快捷方式 **「蓝海之约」**。
点击快捷方式：

1. 若 DSH Web 已在 `127.0.0.1:3080` 运行 → 直接打开浏览器进入 DeepSeek Harness；
2. 若未运行 → 自动以 `npx --verbose @deepseek-ai/dsh web` 启动它，随后打开浏览器。

快捷方式图标为打包内 `assets/whale-icon.ico`（蓝发少女 × Deepseek 立绘，含 16–256px 七档尺寸）。

## 目录结构

```text
dsh-blue-sea-launcher/
├── package.json          # DSH bundle 插件元数据
├── README.md             # 本文件
├── cordis.patch.yml      # 插件挂载声明
├── lib/
│   └── index.js          # 宿主侧插件本体（创建/修复桌面快捷方式）
├── bin/
│   ├── launch.cmd        # 快捷方式指向的启动器外壳
│   └── launch.ps1        # 启动器本体（检活 + 单实例锁 + 启动 + 轮询就绪 + 开浏览器）
└── assets/
    ├── whale-icon.ico    # 快捷方式图标（多尺寸）
    └── whale-icon.png    # 图标源图（透明底 270×270）
```

## 安装

本地开发安装（推荐，源码目录装进 web profile）：

```powershell
dsh plugin --profile web add link:D:\软件创意\综合聊天\dsh-blue-sea-launcher
```

说明：

- `dsh plugin` 会把它加入 `dsh.profile.bundles`（因为 package.json 声明了 `dsh.bundle.patch`）
- `link:` 记录绝对路径——**之后移动了插件目录要重新 add**
- 安装完成后需**重启 `dsh web`**（bundle 层只在启动时组合），桌面即出现「蓝海之约」

发布到 npm 后任意机器安装：

```powershell
dsh plugin --profile web add dsh-blue-sea-launcher
```

## 配置

不写配置即用默认值。可在 profile 的 `cordis.patch.yml`（或 bundle patch）里覆盖：

```yaml
- insert:
    - id: dsh-blue-sea-launcher
      name: dsh-blue-sea-launcher
      config:
        shortcutName: 蓝海之约      # 快捷方式名（不含 .lnk）
        url: http://127.0.0.1:3080   # 打开地址
        port: 3080                   # 检活端口
```

## 卸载

```powershell
dsh plugin --profile web remove dsh-blue-sea-launcher
```

注意：卸载不会删除已生成的「蓝海之约」快捷方式（它先于 DSH 启动，属于你的桌面入口）。
如不需要，手动删除桌面上的「蓝海之约」即可。

## 变更记录

- **v0.1.4**（自适应 dsh 版本更新）：不再依赖固定的启动日志格式——从服务输出里**宽匹配**
  抓取地址（优先带 token 的），并且**打开前先访问验证**（200/302 才算就绪；401/错误则继续
  等待重试，最长 60 秒）。因此 dsh 升级改变登录方式或日志样式时启动器**自动适应**，
  无需手动换代；任何一步失败都会退化为"打开裸地址"并给出提示。
- **v0.1.3**（修复"第一次打开失败"）：旧逻辑在**端口一打开**就立即用地址打开浏览器,但新版
  dsh 的 token 认证服务要到启动日志打印 `dsh web:` 那行后才真正就绪——第一次访问会
  撞上未就绪的认证层,显示英文错误页/401(刷新无效,过一会儿再回车才成功)。
  现在启动器**只等日志里出现 token 地址行**(这才是官方定义的"就绪信号")后再打开,
  并附加 0.6 秒缓冲,确保一次到位;45 秒未等到才回退裸地址。
- **v0.1.2**（适配新版 dsh web 登录）：新版 `dsh web` 启动时打印**带 token 的地址**
  （`http://127.0.0.1:3080/?t=…`），浏览器须先访问它换取签名 Cookie 才能进入页面，
  裸地址会收到 401。启动器现在会把服务输出重定向到日志
  （`<DSH_HOME>/dsh-web-url.log`），解析出 token 地址并用它打开浏览器；服务已运行时
  若日志里存有本进程的 token 地址也会优先使用。旧版 dsh（无 token）依旧兼容（打开裸地址）。
- **v0.1.1**（修复"打开两次"）：dsh web 启动时默认会自己打开浏览器（`openBrowser`）。
  启动器现在启动服务器时附带 `--no-open`，只由启动器打开一次浏览器；并改为轮询端口就绪
  （最多 30 秒）后打开，而非固定等待 4 秒；新增单实例互斥锁，双击/重复点击不会再
  重复启动服务器或重复打开页面。

## 常见问题

- **点一次开了两个页面**：已修复（见上方变更记录）。注意：如果**你自己**在终端里用
  `npx --verbose @deepseek-ai/dsh web` 启动（不带 `--no-open`），dsh web 会按原生
  行为自动打开一次浏览器，这是 DSH 本身的行为，不是快捷方式的。
- **打开提示 401 未经授权**：确认用的是 v0.1.2 启动器（新版本会自动使用带 token 的地址）。
  若服务是**手动**在终端启动的（终端没被启动器接管输出），快捷方式读不到 token 日志——
  改用启动器启动服务，或手动访问一次终端打印的带 token 地址。
- **快捷方式没出现**：确认 `dsh --profile web --dump-config | Select-String blue-sea` 能看到
  `dsh-blue-sea-launcher`；重启 `dsh web` 后看控制台 `blue-sea-launcher` 日志。
- **图标没变化**：资源管理器图标缓存延迟——桌面按 F5；仍旧就重启 `explorer.exe` 或注销一次。
- **点击后打不开**：确认 npx 可用；若改了端口，`launch.cmd` 按 `127.0.0.1:port` 检活。
- **换图标**：替换 `assets/whale-icon.ico`（多尺寸 ico），或改配置让其指向你的 ico 文件后重启。
