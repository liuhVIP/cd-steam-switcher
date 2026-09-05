# 版本数据文件

版本登记数据只存放在根目录的 `versions.json`，程序代码不内嵌版本号。

每个条目至少包含：

```json
{
  "id": "2.01.00",
  "label": "2.01.00",
  "release_date": "2026-09-04",
  "buildid": 25116796,
  "manifest": "3540302611239512787",
  "source": "steam-log",
  "verified": true
}
```

发布新版本时只需更新 JSON 的 `versions` 数组。开发者也可以使用：

```powershell
. .\lib\Registry.ps1
Merge-VersionRegistryFile -UpdatePath .\new-versions.json
```

程序启动时仍会从本机 Steam ACF 和 `content_log.txt` 自动补登记未知 Build/Manifest。
