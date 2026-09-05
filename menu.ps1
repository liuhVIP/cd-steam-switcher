# 红沙版本切换器 - 主入口（中文 CMD 交互菜单 + doctor 子命令）
#Requires -Version 3.0
param(
    [Parameter(Position = 0)][string]$Action = 'menu',
    [switch]$Doctor
)

$script:RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:RootDir 'lib\Common.ps1')
. (Join-Path $script:RootDir 'lib\Vdf.ps1')
. (Join-Path $script:RootDir 'lib\Acf.ps1')
. (Join-Path $script:RootDir 'lib\SteamEnv.ps1')
. (Join-Path $script:RootDir 'lib\Registry.ps1')
. (Join-Path $script:RootDir 'lib\Ui.ps1')
. (Join-Path $script:RootDir 'lib\Installer.ps1')
. (Join-Path $script:RootDir 'lib\Lock.ps1')
. (Join-Path $script:RootDir 'lib\SteamConsole.ps1')
Set-ConsoleEncoding

function Get-LockStateText {
    $lockFile = Join-Path $script:RootDir 'state\lock.json'
    if (Test-Path -LiteralPath $lockFile -PathType Leaf) {
        try {$s=Get-Content -Raw -LiteralPath $lockFile|ConvertFrom-Json;if(!$s.VersionId -or !$s.Manifest){return '锁定状态损坏（请执行解锁恢复）'};$id=$s.VersionId;$build=if($s.BuildId){' Build '+$s.BuildId}else{''};return ('已锁定到 '+$id+$build)} catch { return '锁定状态损坏（请执行解锁恢复）' }
    }
    return '未锁定'
}

function Get-StatusHeaderText {
    try {
        $env2 = Get-CrimsonDesertEnvironment
    } catch {
        return '当前游戏: 未找到 Crimson Desert 安装'
    }
    if (-not $env2.AcfFound) {
        return '当前游戏: 未找到 Crimson Desert 安装（appmanifest_3321460.acf）'
    }
    $versionText = $env2.BuildId
    if (-not [string]::IsNullOrWhiteSpace($env2.DepotManifest)) {
        $versionText += '  manifest=' + $env2.DepotManifest
    }
    $lockText = Get-LockStateText
    if ($env2.AcfReadOnly -and $lockText -eq '未锁定') { $lockText = 'ACF 只读(手动)' }
    return ('当前游戏: ' + $env2.Name + '  Build=' + $versionText + '  状态: ' + $lockText)
}

function Show-Doctor {
    Write-Host '==== 环境检测 doctor ====' -ForegroundColor Cyan
    $env2 = $null
    try {
        $env2 = Get-CrimsonDesertEnvironment
    } catch {
        Write-StepErr ('检测失败: ' + $_.Exception.Message)
        return
    }

    Write-StepInfo ('Steam 安装目录: ' + $(if ($env2.SteamPath) { $env2.SteamPath } else { '未找到' }))
    Write-StepInfo ('Steam 库目录: ' + $(if ($env2.LibraryPaths) { ($env2.LibraryPaths -join '; ') } else { '未找到' }))
    Write-StepInfo ('ACF 文件: ' + $(if ($env2.AcfPath) { $env2.AcfPath } else { '未找到 appmanifest_3321460.acf' }))

    if ($env2.AcfFound) {
        Write-StepInfo ('游戏名: ' + $env2.Name)
        Write-StepInfo ('安装目录: ' + $env2.InstallDir)
        Write-StepInfo ('游戏目录: ' + $env2.GameDir)
        Write-StepInfo ('主程序: ' + $env2.GameExe + $(if ($env2.GameExeExists) { ' (存在)' } else { ' (缺失!)' }))
        if ($env2.ExeFileVersion) { Write-StepInfo ('主程序 FileVersion: ' + $env2.ExeFileVersion) }
        Write-StepInfo ('BuildID: ' + $env2.BuildId)
        Write-StepInfo ('Depot ' + $env2.DepotId + ' manifest: ' + $env2.DepotManifest)
        Write-StepInfo ('游戏语言(UserConfig): ' + $env2.Language)
        Write-StepInfo ('安装完成时间: ' + $env2.LastUpdated)
        Write-StepInfo ('ACF 只读: ' + $(if ($env2.AcfReadOnly) { '是' } else { '否' }))
    } else {
        Write-StepWarn '未检测到游戏 ACF。请确认：1) 本机已安装并登录 Steam；2) 账号拥有并已安装 Crimson Desert；3) 以同一 Windows 用户运行。'
    }

    if ($env2.ActiveUser) {
        Write-StepInfo ('当前 Steam 账号: ' + $env2.ActiveUser.AccountName + '  (' + $env2.ActiveUser.SteamId64 + ')' + $(if ($env2.ActiveUser.IsActive) { '  [活动]' } else { '  [最近登录]' }))
    } else {
        Write-StepWarn '未找到 Steam 登录账号（可能未登录或 loginusers.vdf 缺失）。'
    }
    Write-Host ''
}

function Show-Placeholder {
    param([string]$ItemName)
    Write-StepWarn ($ItemName + '：该功能在后续 Sprint 实现（见 steam-version-switcher-plan.md），当前仅为界面骨架。')
}

function Show-Versions {
    $items=@(Get-VersionList)
    if(!$items.Count){Write-StepWarn '登记表为空';return $null}
    for($i=0;$i -lt $items.Count;$i++){Write-Host (" {0}) {1}  Build {2}  manifest {3}" -f ($i+1),$items[$i].label,$items[$i].buildid,$items[$i].manifest)}
    $n=0;[int]::TryParse((Read-Host '选择编号'),[ref]$n)|Out-Null
    if($n -ge 1 -and $n -le $items.Count){$items[$n-1]}
}
function Show-RegisterCurrent {
    $e=Get-CrimsonDesertEnvironment
    if(!$e.AcfFound){Write-StepWarn '未找到当前安装';return}
    $found=Find-VersionByManifest -Manifest $e.DepotManifest
    if($found){Write-StepOk ('已登记: '+$found.label);return}
    $label=Read-Host ('当前 Build '+$e.BuildId+' / manifest '+$e.DepotManifest+'，输入版本号(如 2.01.01)')
    try { Register-VersionEntry ([pscustomobject]@{id=$label;label=$label;release_date=(Get-Date -Format yyyy-MM-dd);buildid=[int64]$e.BuildId;manifest=$e.DepotManifest;exe_sha256='';notes='本地安装登记';source='local-acf';verified=$true})|Out-Null;Write-StepOk '登记成功' } catch { Write-StepErr $_.Exception.Message }
}
function Show-EngineSettings { Write-Host 'Steam 客户端控制台模式无需单独登录；请选择 0 返回';Read-Host '按回车返回'|Out-Null }

function Show-InteractiveMenu {
    while ($true) {
        Clear-Host
        Write-Host '==============================================' -ForegroundColor Cyan
        Write-Host (T '   红沙版本切换器 v0.1.0' '   Crimson Desert Version Switcher v0.1.0') -ForegroundColor Cyan
        Write-Host '==============================================' -ForegroundColor Cyan
        Write-Host (Get-StatusHeaderText)
        Write-Host ''
        Write-Host (T ' 1) 查看/检测当前版本与 Steam 环境' ' 1) Check game and Steam environment')
        Write-Host (T ' 2) 选择并下载历史版本（2.0x 列表 + 下载进度）' ' 2) Download a historical version (2.x)')
        Write-Host (T ' 3) 切换到最新版本' ' 3) Switch to latest version')
        Write-Host (T ' 4) 解锁并恢复 Steam 最新版' ' 4) Unlock and restore Steam latest')
        Write-Host (T ' 5) 锁定状态 / 开始游戏' ' 5) Lock status / launch game')
        Write-Host (T ' 6) 登记当前版本' ' 6) Register current version')
        Write-Host (T ' 7) 探测 manifest' ' 7) Probe manifest')
        Write-Host (T ' 8) 设置' ' 8) Settings')
        Write-Host (T ' 0) 退出' ' 0) Exit')
        Write-Host ''
        $choice = Read-Host '请选择'
        switch ($choice.Trim().ToLowerInvariant()) {
            '1' { Show-Doctor }
            '2' { $v=Show-Versions; if($v){try{$e=Get-CrimsonDesertEnvironment;$root=Select-DownloadDrive -RequiredBytes 150GB;Set-DepotDownloadRoot -SteamPath $e.SteamPath -Root $root|Out-Null;$cmd=Get-SteamConsoleCommand $v;$content=Join-Path $root ('app_3321460\depot_3321461');$estimate=Get-EstimatedGameSize -GameDir $e.GameDir;if($estimate -gt 0){Write-StepInfo ('总体积估算依据当前游戏目录: '+(Format-Bytes -Bytes $estimate))}else{$estimate=148GB;Write-StepWarn '无法读取当前游戏大小，使用默认估算 148 GB。'};Write-Host '';Write-StepInfo ('下载内容目录: '+$content);Write-StepInfo '请在 Steam 控制台粘贴并执行以下命令:';Write-Host $cmd -ForegroundColor Yellow;if(Copy-SteamConsoleCommand $cmd){Write-StepInfo '命令已复制到剪贴板，请在 Steam 控制台按 Ctrl+V，再按 Enter。'}else{Write-StepWarn '自动复制失败，请手动复制上面的命令。'};Start-SteamConsole -SteamPath $e.SteamPath;Read-Host '确认已在 Steam 控制台按 Enter 执行命令后，回到此处按回车开始监控'|Out-Null;Wait-SteamDepotDownload -Path $content -EstimatedTotalBytes $estimate|Out-Null;if(Test-SteamDepotDownloaded $content){Write-StepOk ('检测到下载内容: '+$content);if($e.GameDir -and ((Read-Host '是否安装并锁定此版本？(Y/N)').Trim().ToUpperInvariant() -eq 'Y')){Install-DownloadedVersion -Source $content -GameDir $e.GameDir|Out-Null;Set-VersionLock -Environment $e -Version $v;Write-StepOk '安装并锁定完成'}}else{Write-StepWarn '尚未检测到 Depot 文件，请确认 Steam 控制台命令已执行并下载完成'}}catch{Write-StepErr $_.Exception.Message}} }
            '3' { $v=(Get-VersionList|Select-Object -First 1);if($v){Write-StepInfo ('最新登记版本: '+$v.label);Show-Placeholder '切换到最新版本（需 Steam 更新）'} }
            '4' { try{$e=Get-CrimsonDesertEnvironment;if($e.AcfPath){Clear-VersionLock -AcfPath $e.AcfPath;Write-StepOk '已解锁并恢复 ACF'}else{Write-StepWarn '未找到 ACF'}}catch{Write-StepErr $_.Exception.Message} }
            '5' { $s=Join-Path $script:RootDir 'state\lock.json';if(Test-Path $s){Write-StepInfo ('锁定状态: '+(Get-Content -Raw $s))}else{Write-StepInfo '当前未锁定'} }
            '6' { Show-RegisterCurrent }
            '7' { Show-Placeholder 'manifest 探测（请使用 Steam 客户端控制台）' }
            '8' { Show-EngineSettings }
            '0' { Write-StepOk '再见'; return }
            'q' { Write-StepOk '再见'; return }
            default { Write-StepWarn '无效选择' }
        }
        Write-Host ''
        Read-Host '按回车返回菜单' | Out-Null
    }
}

if ($Doctor -or $Action -in @('doctor', 'info', '检测')) {
    Show-Doctor
} else {
    try {
        $autoEnv=Get-CrimsonDesertEnvironment
        $autoLog=Get-SteamContentLogPath -SteamPath $autoEnv.SteamPath
        if($autoEnv.AcfFound){Sync-VersionRegistryFromEnvironment -Environment $autoEnv -LogPath $autoLog|Out-Null}
        Sync-VersionRegistryFromSteamDb|Out-Null
        $activeTask=Find-ActiveSteamDepotDownload -SteamPath $autoEnv.SteamPath
        if($activeTask){
            $autoRoot=Get-ConfiguredDepotRoot -SteamPath $autoEnv.SteamPath
            $autoContent=Join-Path $autoRoot 'app_3321460\depot_3321461'
            Write-StepInfo ('检测到 Steam 正在下载 Depot，自动接续监控: '+$autoContent)
            Wait-SteamDepotDownload -Path $autoContent -EstimatedTotalBytes $activeTask.Total -SteamLogPath $activeTask.LogPath|Out-Null
        }
    } catch { Write-StepWarn ('自动接续检查失败: '+$_.Exception.Message) }
    Show-InteractiveMenu
}
