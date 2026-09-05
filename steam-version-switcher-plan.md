# Plan: 红色沙漠 Steam 版本切换器（独立全自动工具）

**Generated**: 2026-09-04（技术栈按 PowerShell 调整）
**Estimated Complexity**: High
**状态**: 需求已确认；Sprint 1 骨架已完成（doctor/ACF/env，pwsh7 与 Windows PowerShell 5.1 测试通过）；引擎 DepotDownloader 3.4.0 已随包内置并记录 SHA-256；下一步待确认后进入 Sprint 2

## 需求（已确认）

- 独立工具，与 cdmm 模组加载器无耦合，单独维护与发布。
- 项目目录：`T:\python_pro\cd_steam_switcher\`；工具名：**红沙版本切换器**。
- 让玩家用 Steam 版本自由“回退到历史版本”并锁定；锁定可随时解除、一键回到最新。
- 下载**全自动**并显示**详细进度**；中文 CMD 交互菜单。
- 自动获取最新版本号；登记表只收录 **2.0x**（2.00.00、2.00.01、2.0.02、2.01.00），1.x 不收；
  列表按时间**倒序（最新在上）**。
- 登录流程必须让用户放心（防“盗号/钓鱼”观感）。

## 技术栈：PowerShell vs Python（结论：主流程用 PowerShell 5.1 兼容）

| 维度 | PowerShell（5.1 兼容） | Python |
| --- | --- | --- |
| 玩家端运行时 | **Win10/11 自带，零安装** | 需打包 Nuitka/PyInstaller exe（几十~上百 MB，杀软误报风险） |
| 脚本可审计性 | **源码即开源，玩家可自查，信任度高** | exe 黑盒，与“防被盗号”宣传相悖 |
| 开发/测试 | 一般；可用系统自带 Pester 3.4 写回归 | 更顺（pytest） |
| 中文控制台 | 需 UTF-8 BOM + chcp 65001（可解决） | 同样要处理控制台编码 |
| 大文件拷贝/哈希 | robocopy + Get-FileHash，性能在磁盘 | 需调 robocopy/hashlib |
| Windows/注册表/ACF 操作 | 原生顺手 | 要写 Win32 逻辑 |
| 后续扩展 GUI | 弱 | 强 |

结论：本项目定位是“玩家双击即用的 Windows 小工具”，**PowerShell 5.1 兼容**最合适——
零依赖、可读可审计、没有打包与杀软顾虑（同类工具 Crimson Desert Update Guard 亦为 PS）。
Python 只在未来要做 GUI/更复杂 UI 时再考虑。引擎本身仍是第三方开源 DepotDownloader（C#），
与工具壳语言无关。

## 语言与编码约定（写代码时必须遵守）

- 所有 `.ps1` 文件保存为 **UTF-8 with BOM**（Windows PowerShell 5.1 中文不乱码的前提）。
- `run.bat` 用 `chcp 65001` + `powershell -NoProfile -ExecutionPolicy Bypass -File menu.ps1`，
  bat 文件本身只用 ASCII 内容（路径/输出全部交给 ps1），避免 .bat 中文编码问题。
- 控制台输出前 `[Console]::OutputEncoding = UTF8`；输入用 `[Console]::InputEncoding` 同步。
- 密码输入用 `Read-Host -AsSecureString`（不回显）；日志写 UTF-8。

## 登录界面归属（引擎自带 vs 我们自写）

DepotDownloader 自带的是**控制台英文提示 + `-qr` 二维码**，没有中文 GUI。分工：
- **引擎负责**：登录协议、Steam Guard、二维码生成、会话保存（`-remember-password`）。
- **我们负责**：中文登录向导壳（预填当前 Steam 账号、扫码/账密、密码掩码、登录前须知、
  会话状态、一键注销），以及登录完成后转静默下载。

```text
[需要 Steam 登录才能下载历史版本]

 已检测到当前 Steam 账号: liuho (76561198863912748)  ← 自动预填
 请确认这就是拥有《红色沙漠》的账号。

 登录方式:
 [1] 用 Steam 手机 App 扫码（推荐，不输入密码）
 [2] 输入账号密码（等同在 Steam 客户端登录一次）
 [3] 使用上次保存的会话（如已登录过）
 [0] 返回（不登录也能用：查看/锁定/解锁等不下载功能）

 密码输入为掩码(******)，不回显、不写日志。
 凭证只发往 Valve 官方登录服务器；本工具无任何上传。
```

- 扫码：调用引擎 `-qr` 在独立子控制台窗口显示二维码，用 Steam 手机 App 扫；
  成功后引擎 `-remember-password` 保存会话并退出。
- 账密：我们在主菜单掩码输入，把 `-username/-password` 传给引擎（不落盘、不进日志）。
- 已存会话：显示“上次登录账号+时间”，选择后跑轻量自检（`-manifest-only`）确认可用。
- 错误给中文：账号/密码错、Guard 失败、未拥有游戏、manifest 被屏蔽、会话过期。
- 菜单“设置→注销登录”删除引擎会话；README 说明零遥测 + 凭证只发 Valve + 开源地址。

## 2.0x 版本登记（已实锤的 manifest）

| 版本 | 发布时间 | BuildID | Manifest ID | 证据 |
| --- | --- | --- | --- | --- |
| **2.01.00** | 2026-09-04 | 25116796 | `3540302611239512787` | 本机 ACF+日志；Steam 新闻 2.01.00 |
| **2.0.02**（2.00.x 末版） | 2026-09-01 | 25050808 | `2880351385118582388` | 用户提供；日志 finished update(Build 25050808)；AGENTS 记 2.0.02 |
| **2.00.01**（热修） | 2026-08-28 | 24994088 | `1352954998473096876` | 本机日志；新闻 hotfix 2.00.01（≈8/27-28） |
| **2.00.00**（Enhanced 首版） | 2026-08-25 | 24934353 | `1623358805547317954` | SteamDB 8-26 快照 public build=24934353；本机 8-28 安装同一 build |

> 1.x（1.01.03/1.04.1/1.12）等更早版本按需求确认排除。“2.0.02”沿用 loader 作者 2026-09-01
> 记录名；官方若改叫法只改 label 不影响 manifest。

## 下载引擎选型

| 方案 | 全自动 | 进度 | 凭证 | 结论 |
| --- | --- | --- | --- | --- |
| Steam 控制台 | 否 | 无 | 复用当前客户端 | 仅“高级/后备”模式 |
| SteamCMD（官方） | 可脚本化 | 无百分比 | 需登录 | 不做主引擎 |
| **DepotDownloader 3.4.0（SteamRE/开源）** | **是** | **逐文件/分块** | 扫码或账密一次性 | **主引擎** |
| 自研 C#（SteamKit2） | 是 | 自绘 | 同上 | 二期可选 |

关键参数：`-app 3321460 -depot 3321461 -manifest <id>`、`-qr / -no-mobile`、
`-username / -password / -remember-password`、`-dir`、`-manifest-only`、`-filelist`、
`-validate`、`-loginid <随机>`。

**引擎内置（2026-09-05 已落实）**：DepotDownloader 3.4.0（windows-x64 自包含）已提前下载进本项目，
用户使用期**不会联网下载**引擎。来源：官方 GitHub Release `DepotDownloader_3.4.0`
（https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-windows-x64.zip）。
- 原包 `vendor/DepotDownloader-windows-x64-3.4.0.zip`：33,474,005 字节；SHA-256
  `41C9E9F0DF54B3AD02E67A11726756E5C73283BD7C2E1B04ACFA5AE4C2ED3767`（记录于 `vendor/SHA256SUMS.txt`）。
- 已解压到 `depotdownloader/`：单文件 `DepotDownloader.exe`（78,840,739 字节，FileVersion 3.4.0.0，
  ProductVersion `3.4.0+c553ef4d60c00a4f5fd16c9fe017f569001589ff`）+ `LICENSE`；exe SHA-256
  `6281279EFCE8F1E20DB9532A58E42382F81AFB9E3827A8B965FFCB43FBE4531F`（记录于 `depotdownloader/SHA256SUMS.txt`）。
- 工具运行前校验本地 exe 的 SHA-256 与随包记录一致；缺失或校验失败给中文提示（建议重新获取发布包），
  不自动联网下载。winget 自装只作为备选说明保留。

## 目标目录与交付物（PowerShell 版）

```text
T:\python_pro\cd_steam_switcher\
  menu.ps1                      # CMD 交互菜单主入口（中文，UTF-8 BOM）
  run.bat                       # 双击包装：chcp 65001 + -ExecutionPolicy Bypass（纯 ASCII）
  lib/
    SteamEnv.ps1                # 注册表 SteamPath/当前账号、libraryfolders.vdf、游戏/ACF 定位
    Acf.ps1                     # appmanifest_3321460.acf 解析/改写/备份/只读
    Registry.ps1                # versions.json 倒序读写、登记当前版本（仅 2.0x）
    Downloader.ps1              # 引擎封装：登录向导/子进程进度解析/续传/校验/注销
    Installer.ps1               # depot -> 游戏目录替换（保留非游戏内容）+ dry-run 计划
    Lock.ps1                    # 锁定/解锁/回到最新/受保护启动器/状态机
    Latest.ps1                  # 最新版本号自动获取（Steam 新闻 RSS/ACF 变更）
    Ui.ps1                      # 中文菜单、进度条、掩码输入、二次确认
  depotdownloader/              # 引擎（发布包内置，不联网下载；附 SHA-256 记录）
  state/                        # ACF 备份、锁状态、切换记录、引擎会话配置
  versions.json                 # 版本登记表（倒序，仅 2.0x）
  test/
    Acf.Tests.ps1               # Pester 3.4 语法（Win10/11 自带）
    SteamEnv.Tests.ps1
    Registry.Tests.ps1
    Installer.Tests.ps1         # 伪 depot/伪游戏树 dry-run
  README.md
```

## 登记表 versions.json（首发 4 条，倒序：最新在上）

```json
{
  "app_id": 3321460,
  "depot_id": 3321461,
  "game_dir_name": "Crimson Desert",
  "versions": [
    { "id": "2.01.00",  "label": "2.01.00",              "release_date": "2026-09-04", "buildid": 25116796, "manifest": "3540302611239512787", "exe_sha256": "4D99C15C58BD20A94D354D10AE395D1FAC777D59EF52CBA8080DC3FC8DC6F454", "notes": "当前最新；v9.3.9 加载器对应表结构", "source": "local-acf", "verified": true },
    { "id": "2.0.02",   "label": "2.0.02（2.00.x 末版）", "release_date": "2026-09-01", "buildid": 25050808, "manifest": "2880351385118582388", "exe_sha256": "", "notes": "用户提供 manifest；日志实锤", "source": "steam-log", "verified": true },
    { "id": "2.00.01",  "label": "2.00.01（热修）",        "release_date": "2026-08-28", "buildid": 24994088, "manifest": "1352954998473096876", "exe_sha256": "", "notes": "新闻 hotfix 2.00.01", "source": "steam-log", "verified": true },
    { "id": "2.00.00",  "label": "2.00.00（Enhanced 首版）", "release_date": "2026-08-25", "buildid": 24934353, "manifest": "1623358805547317954", "exe_sha256": "", "notes": "SteamDB 8-26 快照 public build=24934353", "source": "steamdb-snapshot", "verified": true }
  ]
}
```

- 只允许带版本号的条目入库；始终倒序（最新在上）。
- 版本表只经两条途径增长：Steam 更新后自动“登记当前版本”；手动补充（需 label+manifest+来源）。
- `exe_sha256` 用于下载后指纹校验（2.01.00 已采集，其余装过一次自动补齐）。

## CMD 交互菜单（中文，倒序展示）

```text
==== 红沙版本切换器 v0.1.0 ====
当前游戏: 2.01.00 (Build 25116796)  状态: 未锁定

 1) 查看/检测当前版本与 Steam 环境
 2) 选择并下载历史版本（2.0x 列表，最新在上 + 下载进度）
 3) 切换到最新版本（自动识别并锁定）
 4) 解锁并恢复 Steam 最新版
 5) 锁定状态 / 用“锁定启动器”直接开始游戏
 6) 登记当前版本 / 手动补充带版本号条目
 7) 探测一个 manifest（只查可下载性/体积/指纹，不下全量）
 8) 设置（登录、注销登录、下载目录、引擎、代理）
 0) 退出
```

下载页实时刷新：`[=====>      ] 47.3%  61.2/129.4 GB  38.5 MB/s  剩余 29:41  文件 120/267`。

## 核心流程

### A. 回退并锁定到某 2.0x 版本
1. 前置检查：游戏未运行；磁盘空间（约 1.5×游戏体积）；ACF 备份就绪。
2. 登录/确认会话（默认扫码；见登录设计）。
3. `DepotDownloader ... -manifest <id> -dir <暂存> -loginid <随机>` 全自动下载，中文进度；
   完成后 `-validate` 并比对 exe SHA-256。
4. 完全退出 Steam。
5. 替换：depot 覆盖到 `steamapps\common\Crimson Desert`，仅删除与 depot 顶层同名旧条目，
   保留 `mods`、`.cdloader` 及 depot 不存在的用户内容；先出 dry-run 清单。
6. 改写 ACF：`InstalledDepots.3321461.manifest` → 目标 manifest、`buildid` → 目标 buildid、
   `AutoUpdateBehavior` → 仅启动时更新；写前备份。
7. 硬锁：ACF 只读 + 状态记录；生成“锁定启动器”（直启 `bin64\CrimsonDesert.exe`）。
8. 重开 Steam：游戏内确认版本；Steam 静置与点“开始游戏”均不触发回滚更新。

### B. 解锁并回到最新
1. 移除 ACF 只读；恢复 `state/` 里原 ACF 备份；清锁状态。
2. 用 Steam“开始游戏”/“验证文件完整性”更新到最新。
3. 完成后自动“登记当前版本”。

### C. 自动获取最新版本号
- Steam 官方新闻 RSS（`steamcommunity.com/games/3321460/rss/`）解析最新“版本 x.xx”标题。
- Steam 更新后 ACF 必记录最新 manifest+buildid；工具检测变化即自动登记。
- 下载“最新”无需预先知道编号：引擎不带 `-manifest` 即下载当前版本。

## 锁定原理与待实机验证点

- 锁定 = ACF manifest/buildid 指向目标 + 只读 ACF + “仅启动时更新”策略 + 只用受保护启动器。
- 开工前先小实验实机确认：Steam 接受“ACF manifest=历史 manifest 且本地文件一致”不触发修复；
  只读 ACF 阻断自动更新效果；改 ACF 必须完全退出 Steam；`AutoUpdateBehavior` 字段语义；
  锁定启动器直启 exe 在 Steam 在线/离线表现。

## Sprint 计划

### Sprint 1: Steam 环境与 ACF 基础（doctor）
- 1.1 项目骨架 + `run.bat`/`menu.ps1` 中文菜单框架（UTF-8 BOM）
- 1.2 `SteamEnv.ps1`：SteamPath/当前账号、libraryfolders.vdf、游戏与 ACF 定位
- 1.3 `Acf.ps1`：ACF 解析/改写/备份/只读（样例回写不丢字段）
- 1.4 `doctor` 接通
**验收**：本机 `doctor` 与 ACF 一致；`Acf.Tests.ps1`、`SteamEnv.Tests.ps1`（Pester 3.4）通过。

### Sprint 2: 登记表与下载引擎
- 2.1 `versions.json` 首发 4 条 2.0x（倒序）+ `Registry.ps1`
- 2.2 引擎随包内置 + 完整性校验（SHA-256 记录）+ `Downloader.ps1` 登录向导（预填/扫码/账密/记住/注销）
- 2.3 下载子进程输出解析与进度条、断点续传、日志
- 2.4 `-manifest-only`/`-filelist` 探测
**验收**：能真实下载当前版本并显示进度；登录/注销全流程走查；Registry 单测通过。

### Sprint 3: 替换与锁定
- 3.1 前置检查；3.2 `Installer.ps1` 替换与保留策略（dry-run）
- 3.3 `Lock.ps1`：退出 Steam→改 ACF→只读→启动器→重开 Steam
- 3.4 实机：用 2.0.02（2880351385118582388）真实回退并锁定；`mods`/`.cdloader` 保留；解锁回 2.01.00
**验收**：端到端切换+锁定成功且可逆。

### Sprint 4: 解锁恢复、菜单与最新版
- 4.1 unlock/restore-latest + ACF 恢复；4.2 完整菜单与二次确认；4.3 最新版自动获取与登记
**验收**：回退→锁定→解锁→恢复最新全链路回归。

### Sprint 5: 测试、文档与发布
- 5.1 补测试（伪树 dry-run、ACF 往返、registry 倒序/仅 2.0x 校验）
- 5.2 README（原理/登录安全说明/风险/如何贡献新版本号）
- 5.3 实机验收清单 + 发布包（脚本+引擎+登记表+README，zip）
**验收**：真实机器完整走一遍；发布包结构可复现。

## Testing Strategy

- 单元（Pester 3.4，Win10/11 自带）：ACF 往返、library 解析、替换保留策略（伪树）、
  registry 倒序/仅 2.0x。
- 集成：dry-run 替换计划、manifest-only 探测、登录失败/成功文案。
- 实机：下载 2.0.02 → 回退锁定 → 进游戏看版本 → 解锁恢复 2.01.00。
- 回归：锁定后 Steam 静置/点开始游戏不触发更新；存档/云存档备份提示有效。

## 风险与对策

- **旧 manifest 被发行商屏蔽**：先 `-manifest-only` 探测，给中文原因与备选。
- **下载体积**：约 130GB；提示磁盘/时长，断点续传。
- **会话冲突**：独立 `-loginid`；改 ACF 前退出 Steam。
- **锁定失败自动回滚**：Sprint 3 先小改动实机确认锁定机制。
- **账号信任**：默认扫码、零遥测、密码掩码、一键注销、README 附开源地址。
- **版本标签**：只收 2.0x；官方改名只改 label；每次 Steam 更新自动登记。
- **存档/Steam 云**：切换旧版前提示备份存档并建议关闭云存档。
- **第三方引擎**：发布包内置 depotdownloader 并附 SHA-256 记录；用户使用期不联网下载。
- **编码**：ps1 一律 UTF-8 BOM；bat 纯 ASCII；控制台 UTF-8（chcp 65001）。

## 自身回退（工具操作可逆）

- 解锁恢复最新 = 移除只读 + 恢复原 ACF + Steam 校验更新，无需重装。
- `state/` 丢失：手动去 ACF 只读并让 Steam 验证即恢复。
- 写游戏/ACF 前必须有备份与 dry-run 计划文件。
