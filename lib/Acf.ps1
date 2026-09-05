# ACF（appmanifest_*.acf）读写封装：VDF 解析、字段改写、备份、只读锁
#Requires -Version 3.0
. (Join-Path $PSScriptRoot 'Vdf.ps1')

function Read-VdfFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "找不到文件: $Path"
    }
    $text = [System.IO.File]::ReadAllText($Path)
    return (ConvertFrom-VdfText -Text $text)
}

function Write-VdfFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Node
    )
    $text = ConvertTo-VdfText -Node $Node
    if (-not $text.EndsWith([Environment]::NewLine)) { $text += [Environment]::NewLine }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

function Register-SteamAppManifest {
    param(
        [Parameter(Mandatory = $true)][string]$GameDir,
        [Parameter(Mandatory = $true)]$Version,
        [string]$Name = 'Crimson Desert Enhanced',
        [Int64]$SizeOnDisk = 0,
        [string]$LauncherPath = '',
        [string]$SteamPath = '',
        [string]$LastOwner = '',
        [string]$TargetBuildID = ''
    )
    $GameDir = [IO.Path]::GetFullPath($GameDir)
    if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) { throw ('游戏目录不存在: ' + $GameDir) }
    $steamApps = Split-Path (Split-Path $GameDir -Parent) -Parent
    $acfPath = Join-Path $steamApps ('appmanifest_' + $script:AppId + '.acf')
    if(Test-Path -LiteralPath $acfPath -PathType Leaf){try{Set-FileReadOnly -Path $acfPath -ReadOnly $false}catch{}}
    if ($SizeOnDisk -le 0) {
        $SizeOnDisk = [Int64]((Get-ChildItem -LiteralPath $GameDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
    }
    $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    if([string]::IsNullOrWhiteSpace($LauncherPath) -and $SteamPath){$LauncherPath=Join-Path $SteamPath 'steam.exe'}
    if([string]::IsNullOrWhiteSpace($LauncherPath)){try{$sp=Get-SteamInstallPath;if($sp){$LauncherPath=Join-Path $sp 'steam.exe'}}catch{}}
    if([string]::IsNullOrWhiteSpace($TargetBuildID)){$TargetBuildID=[string]$Version.buildid}
    $appState = [ordered]@{
        appid = [string]$script:AppId; Universe = '1'; name = $Name; StateFlags = '4'; installdir = (Split-Path $GameDir -Leaf)
        LastUpdated = [string]$now; LastPlayed = '0'; SizeOnDisk = [string]$SizeOnDisk; StagingSize = '0'; buildid = [string]$Version.buildid
        LastOwner = $LastOwner; DownloadType = '1'; UpdateResult = '0'; BytesToDownload = '0'; BytesDownloaded = '0'; BytesToStage = '0'; BytesStaged = '0'
        TargetBuildID = $TargetBuildID; AutoUpdateBehavior = '1'; AllowOtherDownloadsWhileRunning = '2'; ScheduledAutoUpdate = '0'; StagingFolder = '4'
        InstalledDepots = [ordered]@{ '3321461' = [ordered]@{ manifest = [string]$Version.manifest; size = [string]$SizeOnDisk } }
        SharedDepots = [ordered]@{ '228989' = '228980' }
        UserConfig = [ordered]@{ language = 'schinese'; DisabledDLC = '' }; MountedConfig = [ordered]@{ language = 'schinese'; DisabledDLC = '' }
    }
    if(-not [string]::IsNullOrWhiteSpace($LauncherPath)){
        # 调用方传入的路径可能来自 JSON/命令行而带有重复反斜杠，先规整为 Windows 实际路径。
        $LauncherPath=($LauncherPath -replace '\\\\+','\\')
        $ordered=[ordered]@{}
        $ordered['appid']=$appState['appid'];$ordered['Universe']=$appState['Universe'];$ordered['LauncherPath']=$LauncherPath
        foreach($k in @($appState.Keys)){if($k -ne 'appid' -and $k -ne 'Universe' -and $k -ne 'LauncherPath'){$ordered[$k]=$appState[$k]}}
        $appState=$ordered
    }
    $node = [ordered]@{ AppState = $appState }
    Write-VdfFile -Path $acfPath -Node $node
    return $acfPath
}

function Register-SteamAppManifestFromTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$TemplatePath,
        [Parameter(Mandatory = $true)][string]$GameDir,
        [Parameter(Mandatory = $true)][string]$SteamPath,
        $Version,
        [string]$LastOwner = '0',
        [Int64]$SizeOnDisk = 0
    )
    if(-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)){throw ('找不到 ACF 模板: '+$TemplatePath)}
    $GameDir=[IO.Path]::GetFullPath($GameDir);if(-not (Test-Path -LiteralPath $GameDir -PathType Container)){throw ('游戏目录不存在: '+$GameDir)}
    $steamApps=Split-Path (Split-Path $GameDir -Parent) -Parent;$acfPath=Join-Path $steamApps ('appmanifest_'+$script:AppId+'.acf')
    if(Test-Path -LiteralPath $acfPath -PathType Leaf){try{Set-FileReadOnly -Path $acfPath -ReadOnly $false}catch{}}
    $node=Read-VdfFile -Path $TemplatePath;$state=Get-AcfAppState -Node $node
    if($SizeOnDisk -le 0){$SizeOnDisk=[Int64]((Get-ChildItem -LiteralPath $GameDir -Recurse -File -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum)}
    # 模板保持 Steam 最新版本与完整状态；仅更新本机安装信息。
    Set-VdfPathValue -Node $state -Path @('installdir') -Value (Split-Path $GameDir -Leaf)
    Set-VdfPathValue -Node $state -Path @('SizeOnDisk') -Value ([string]$SizeOnDisk)
    Set-VdfPathValue -Node $state -Path @('StagingSize') -Value '0'
    if(-not [string]::IsNullOrWhiteSpace($LastOwner)){Set-VdfPathValue -Node $state -Path @('LastOwner') -Value $LastOwner}
    Set-VdfPathValue -Node $state -Path @('LauncherPath') -Value ((Join-Path $SteamPath 'steam.exe') -replace '\\\\+','\\')
    Set-VdfPathValue -Node $state -Path @('BytesToDownload') -Value '0';Set-VdfPathValue -Node $state -Path @('BytesDownloaded') -Value '0'
    Set-VdfPathValue -Node $state -Path @('BytesToStage') -Value '0';Set-VdfPathValue -Node $state -Path @('BytesStaged') -Value '0'
    Write-VdfFile -Path $acfPath -Node $node;return $acfPath
}

function Get-BundledAcfTemplate {
    $root = Split-Path -Parent $PSScriptRoot
    $path = Join-Path $root ('templates\appmanifest_' + $script:AppId + '.acf')
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return $null
}

function Restore-BundledLatestAcf {
    param(
        [Parameter(Mandatory = $true)]$Environment,
        [Parameter(Mandatory = $true)][string]$TemplatePath
    )
    if (-not $Environment.AcfPath) { throw '未找到 ACF，无法解除 Steam 更新状态' }
    if (-not (Test-Path -LiteralPath $Environment.AcfPath -PathType Leaf)) { throw ('ACF 文件不存在: ' + $Environment.AcfPath) }
    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) { throw ('找不到内置最新 ACF 模板: ' + $TemplatePath) }
    $stateDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'state'
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $backup = Join-Path $stateDir ('acf_latest_restore_backup_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.acf')
    $n = 1
    while (Test-Path -LiteralPath $backup) {
        $backup = Join-Path $stateDir ('acf_latest_restore_backup_' + (Get-Date -Format yyyyMMdd_HHmmss) + '_' + $n + '.acf')
        $n++
    }
    Copy-FileBackup -Path $Environment.AcfPath -BackupPath $backup
    try {
        $size = [Int64]0
        if ($Environment.GameDir -and (Test-Path -LiteralPath $Environment.GameDir -PathType Container)) {
            $size = [Int64]((Get-ChildItem -LiteralPath $Environment.GameDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
        }
        $steam = [string]$Environment.SteamPath
        if ([string]::IsNullOrWhiteSpace($steam)) { $steam = Get-SteamInstallPath }
        if ([string]::IsNullOrWhiteSpace($steam)) { throw '无法定位 Steam 安装目录' }
        Register-SteamAppManifestFromTemplate -TemplatePath $TemplatePath -GameDir $Environment.GameDir -SteamPath $steam -SizeOnDisk $size | Out-Null
        return $backup
    } catch {
        if (Test-Path -LiteralPath $backup) { Copy-Item -LiteralPath $backup -Destination $Environment.AcfPath -Force }
        throw
    }
}

function Get-VdfPathValue {
    param($Node, [Parameter(Mandatory = $true)][string[]]$Path)
    $cur = $Node
    foreach ($key in $Path) {
        if ($null -eq $cur -or -not ($cur -is [System.Collections.IDictionary]) -or -not $cur.Contains($key)) {
            return $null
        }
        $cur = $cur[$key]
    }
    return $cur
}

function Set-VdfPathValue {
    param($Node, [Parameter(Mandatory = $true)][string[]]$Path, $Value)
    if ($Path.Count -eq 0) { throw 'Path 不能为空' }
    $cur = $Node
    for ($j = 0; $j -lt ($Path.Count - 1); $j++) {
        $key = $Path[$j]
        if ($null -eq $cur -or -not ($cur -is [System.Collections.IDictionary])) {
            throw "中间节点不是字典: $key"
        }
        if (-not $cur.Contains($key) -or -not ($cur[$key] -is [System.Collections.IDictionary])) {
            $cur[$key] = [ordered]@{}
        }
        $cur = $cur[$key]
    }
    $lastKey = $Path[$Path.Count - 1]
    if (-not ($cur -is [System.Collections.IDictionary])) { throw '末尾节点不是字典' }
    $cur[$lastKey] = $Value
}

# ---- ACF 便捷访问 ----

function Get-AcfAppState {
    param($Node)
    if ($null -ne $Node -and $Node.Contains('AppState')) { return $Node['AppState'] }
    return $Node
}

function Get-AcfField {
    param($Node, [Parameter(Mandatory = $true)][string]$Name)
    $state = Get-AcfAppState -Node $Node
    if ($null -eq $state -or -not $state.Contains($Name)) { return $null }
    return $state[$Name]
}

function Get-AcfDepotManifest {
    param($Node, [string]$DepotId = '3321461')
    $state = Get-AcfAppState -Node $Node
    return (Get-VdfPathValue -Node $state -Path @('InstalledDepots', $DepotId, 'manifest'))
}

function Set-AcfDepotManifest {
    param($Node, [string]$DepotId = '3321461', [Parameter(Mandatory = $true)][string]$Manifest)
    $state = Get-AcfAppState -Node $Node
    Set-VdfPathValue -Node $state -Path @('InstalledDepots', $DepotId, 'manifest') -Value $Manifest
}

function Get-AcfBuildId {
    param($Node)
    return (Get-AcfField -Node $Node -Name 'buildid')
}

function Set-AcfBuildId {
    param($Node, [Parameter(Mandatory = $true)][string]$BuildId)
    $state = Get-AcfAppState -Node $Node
    Set-VdfPathValue -Node $state -Path @('buildid') -Value $BuildId
}

# ---- 备份与只读 ----

function Copy-FileBackup {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [switch]$Force
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "源文件不存在: $Path" }
    if ((Test-Path -LiteralPath $BackupPath -PathType Leaf) -and -not $Force) {
        throw "备份文件已存在: $BackupPath（如需覆盖请加 -Force）"
    }
    $dir = Split-Path -Parent $BackupPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -LiteralPath $Path -Destination $BackupPath -Force
}

function Set-FileReadOnly {
    param([Parameter(Mandatory = $true)][string]$Path, [bool]$ReadOnly = $true)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $attrs = $item.Attributes
    if ($ReadOnly) {
        if (-not ($attrs -band [System.IO.FileAttributes]::ReadOnly)) {
            $item.Attributes = $attrs -bor [System.IO.FileAttributes]::ReadOnly
        }
    } else {
        if ($attrs -band [System.IO.FileAttributes]::ReadOnly) {
            $item.Attributes = $attrs -bxor [System.IO.FileAttributes]::ReadOnly
        }
    }
}

function Test-FileReadOnly {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $attrs = (Get-Item -LiteralPath $Path -Force).Attributes
    return (($attrs -band [System.IO.FileAttributes]::ReadOnly) -eq [System.IO.FileAttributes]::ReadOnly)
}
