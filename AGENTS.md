# Crimson Desert Steam 版本切换器：代理开发指南

## 项目概览

- 这是面向 Windows 的 PowerShell 工具，不是 Python 包；最低目标为 **Windows PowerShell 3.0**（代码需兼容 5.1，避免仅 PowerShell 7 才有的语法/命令）。
- 根入口是 `menu.ps1`，启动脚本是 `启动红色沙漠版本切换器v1.0.bat`。
- `lib\` 存放 VDF/ACF 解析、Steam 环境识别、版本登记、下载、安装替换、锁定和 UI 辅助模块。入口通过点源加载模块。
- `versions.json` 是版本登记数据；`VERSION_DATA.md` 说明其格式；`README.md` 是用户文档。

## 常用命令

在项目根目录执行：

```powershell
# 运行全部回归测试（每个测试文件在隔离子进程运行）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\Run-Tests.ps1

# 单独运行测试
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\Vdf.Tests.ps1

# 检测 Steam/游戏环境
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\menu.ps1 -Doctor

# 启动交互菜单
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\menu.ps1
```

测试脚本使用项目自带的轻量断言辅助，不要假设已安装 Pester。修改 `lib\` 后至少运行完整测试集；涉及 Steam 路径、ACF 或安装流程时，再用 `-Doctor` 做手工烟测。

## 修改约定

- 保持 Windows PowerShell 3.0/5.1 兼容性，避免仅 PowerShell 7 支持的新语法；除非有明确理由，不引入外部模块或运行时依赖。
- 文本文件统一 UTF-8；用户可见输出保留中英文切换（使用 `lib\Common.ps1` 的 `T` 函数）。
- 新增功能优先放入对应的 `lib\*.ps1`，由 `menu.ps1` 调用；新增公共函数应有对应测试。
- 版本条目遵守现有校验（2.x/登记格式、manifest 与 buildid 去重），并同步更新相关文档。
- `dist\` 是发布产物，`vendor\_tmp_*` 是研究资料；除非任务明确要求，不要修改或打包它们。

## Steam/文件安全

- 开发和测试优先使用临时目录、`-DryRun` 或只读检测，不要指向真实游戏目录做破坏性实验。
- ACF 锁定必须先备份，再修改 buildid/manifest，并恢复只读属性；保持操作可逆，不直接修改 Steam 原始归档。
- 安装替换涉及整目录移动、备份和回滚；保留异常回滚路径，并默认保留下载缓存。
- `state\` 保存运行时状态/备份，除 `state\.gitkeep` 外通常不应提交；不要提交日志、凭据或本机绝对路径。

## 已确认的产品行为

- 下载后端使用 Steam 官方客户端控制台的 `download_depot 3321460 3321461 <manifest>`，不依赖 DepotDownloader 登录，也不要求用户配置代理。工具负责生成命令、定位内容目录、监控本地写入进度并在重启后接续提示。
- 自定义下载根目录通过 Steam `steamapps\content` 的目录映射实现。修改这部分时必须拒绝覆盖非空的默认目录，并优先显示实际配置的路径。
- 启动时自动接续只针对用户主动执行的 `download_depot 3321460 3321461 ...` 记录；普通 Steam 更新、验证文件或自动更新不能被误判为历史版本下载。
- 版本安装采用整目录替换：空间足够时先将旧游戏目录改名为带时间戳的备份，复制完整 Depot，成功后清理备份；失败时删除半成品并恢复旧目录。空间不足时必须明确显示剩余空间/所需空间，并由用户确认是否删除旧目录，默认取消。
- 安装复制应持续显示文件数、字节数、速度和百分比。安装成功后下载缓存默认保留，只有用户明确输入 `Y` 才删除；`N` 或回车均保留。
- 锁定版本会把 ACF 设为只读。Steam 完整性验证需要临时解锁 ACF，验证完成后再恢复原 BuildID/Manifest 和只读状态；不要把验证失败当作普通下载错误。
- `versions.json` 的 manifest 必须对应 Windows 主 Depot `3321461`；其他平台 Depot（例如 macOS `3321462`）不能加入 Windows 版本列表。

## 提交前检查

1. 检查 `git diff`，确认没有意外的 `state\`、`depots\`、`dist\` 或日志文件。
2. 运行 `test\Run-Tests.ps1` 并确认退出码为 0。
3. 若改动用户流程，更新 `README.md`；若改动版本数据格式，更新 `VERSION_DATA.md`。
4. 在 Windows PowerShell 验证中文输出、含空格路径及 Steam 未安装/ACF 缺失等错误分支。
