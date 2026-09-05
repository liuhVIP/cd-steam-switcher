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

function Get-ToolVersion {
    try {
        $data = Read-VersionRegistry
        if ($data.tool_version) { return [string]$data.tool_version }
    } catch { }
    return '1.0.0'
}

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
        Write-StepInfo '如果 Steam 库位于已断开磁盘或 ACF 无法自动识别，请返回菜单选择“8) 设置游戏目录（自动识别失败时）”手动指定。'
    }

    if ($env2.ActiveUser) {
        Write-StepInfo ('当前 Steam 账号: ' + $env2.ActiveUser.AccountName + '  (' + $env2.ActiveUser.SteamId64 + ')' + $(if ($env2.ActiveUser.IsActive) { '  [活动]' } else { '  [最近登录]' }))
    } else {
        Write-StepWarn '未找到 Steam 登录账号（可能未登录或 loginusers.vdf 缺失）。'
    }
    Write-Host ''
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
function Set-GamePathManually {
    $current = Get-ManualGameDirPath
    if ($current) { Write-StepInfo ('当前手动游戏目录: ' + $current) }
    $path = Read-Host '输入 Crimson Desert 游戏目录（直接回车取消）'
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    try { $saved = Set-ManualGameDirPath -GameDir $path; Write-StepOk ('已保存游戏目录: ' + $saved) }
    catch { Write-StepErr $_.Exception.Message }
}
function Show-ManualLock {
    try {
        $e=Get-CrimsonDesertEnvironment
        if(!$e.AcfPath){throw '未找到 ACF，无法锁定版本'}
        if([string]::IsNullOrWhiteSpace($e.BuildId) -or [string]::IsNullOrWhiteSpace($e.DepotManifest)){throw '当前 ACF 缺少 BuildID 或 manifest，无法锁定'}
        $found=Find-VersionByManifest -Manifest $e.DepotManifest
        $label=if($found){$found.label}else{'未知版本'}
        Write-Host '将锁定当前已安装版本：' -ForegroundColor Cyan
        Write-Host ('  版本: '+$label)
        Write-Host ('  Build: '+$e.BuildId)
        Write-Host ('  Manifest: '+$e.DepotManifest)
        Write-Host ('  游戏目录: '+$e.GameDir)
        if((Read-Host '确认锁定当前版本？(Y/N)').Trim().ToUpperInvariant() -ne 'Y'){return}
        $v=if($found){$found}else{[pscustomobject]@{id=('build.'+$e.BuildId);label=$label;buildid=$e.BuildId;manifest=$e.DepotManifest}}
        Set-VersionLock -Environment $e -Version $v
        Write-StepOk ('已锁定当前版本: '+$label)
    } catch { Write-StepErr $_.Exception.Message }
}
function Ensure-GameEnvironment {
    $env2 = Get-CrimsonDesertEnvironment
    if ($env2.AcfFound) { return $env2 }
    Write-StepWarn '自动未找到 Crimson Desert 安装位置。已有游戏可输入路径；没有安装游戏请输入 N，仍可下载指定版本。'
    while ($true) {
        $path = Read-Host '请输入 Crimson Desert 游戏目录（没有安装游戏请输入 N）'
        if ($path.Trim().ToUpperInvariant() -eq 'N') {
            Write-StepInfo '按无游戏模式继续；可下载指定版本，但低空间模式和安装锁定需先设置游戏目录。'
            return $env2
        }
        if ([string]::IsNullOrWhiteSpace($path)) { Write-StepWarn '未设置游戏目录；相关操作可能无法使用。'; return $env2 }
        try {
            Set-ManualGameDirPath -GameDir $path | Out-Null
            $env2 = Get-CrimsonDesertEnvironment
            if ($env2.AcfFound) {
                Write-StepOk ('已识别并保存游戏目录: ' + $env2.GameDir)
                return $env2
            }
            Write-StepErr '路径已保存，但仍未找到有效的 appmanifest_3321460.acf，请确认输入的是游戏目录。'
        } catch {
            Write-StepErr $_.Exception.Message
        }
    }
}
function Confirm-DeleteDownload { param([string]$Path);$answer=(Read-Host '是否删除已下载的 Depot 文件？默认保留（Y 删除 / N 保留）').Trim().ToUpperInvariant();if($answer -eq 'Y' -and (Test-Path $Path)){Remove-Item -LiteralPath (Split-Path $Path -Parent) -Recurse -Force;Write-StepOk '已删除下载缓存'}else{Write-StepInfo ('已保留下载缓存: '+$Path)} }

function Complete-DownloadedVersion {
 param($Environment,$Content,$Version)
  if($Environment.GameDir){
  if((Read-Host '是否安装并锁定此版本？(Y/N)').Trim().ToUpperInvariant() -eq 'Y'){Install-DownloadedVersion -Source $Content -GameDir $Environment.GameDir|Out-Null;Set-VersionLock -Environment $Environment -Version $Version;Write-StepOk '安装并锁定完成'}
  } else {
  $target=(Read-Host '未检测到游戏目录，请输入安装目标目录（直接回车暂不安装）').Trim().Trim('"')
  if($target){$steam=Resolve-SteamPathForDepot -SteamPath $Environment.SteamPath -Prompt;if([string]::IsNullOrWhiteSpace($steam)){throw '未提供 Steam 根目录，无法创建安装登记'};Install-DownloadedVersion -Source $Content -GameDir $target|Out-Null;$size=Get-DirectoryBytes -Path $target;$latest=(Get-VersionList|Sort-Object {[int64]$_.buildid} -Descending|Select-Object -First 1);$template=Get-BundledAcfTemplate;if([string]::IsNullOrWhiteSpace($template)){throw '内置 ACF 模板缺失，无法创建 Steam 原生安装登记'};$acf=Register-SteamAppManifestFromTemplate -TemplatePath $template -GameDir $target -SteamPath $steam -SizeOnDisk $size|Select-Object -Last 1;Set-ManualGameDirPath -GameDir $target -SkipManifest|Out-Null;$registered=[pscustomobject]@{AcfPath=$acf};Set-VersionLock -Environment $registered -Version $Version;Write-StepOk '安装完成，已使用内置最新 ACF 登记并保存历史版本锁定'}
 }
}

function Show-InteractiveMenu {
    while ($true) {
        Clear-Host
        Write-Host '==============================================' -ForegroundColor Cyan
        $toolVersion = Get-ToolVersion
        Write-Host (T ('   红沙版本切换器 v' + $toolVersion) ('   Crimson Desert Version Switcher v' + $toolVersion)) -ForegroundColor Cyan
        Write-Host (T '   开发者：b站up改名_' '   Developer: b站up改名_') -ForegroundColor DarkGray
        Write-Host '   GitHub: https://github.com/liuhVIP/cd-steam-switcher' -ForegroundColor DarkGray
        Write-Host '==============================================' -ForegroundColor Cyan
        Write-Host (Get-StatusHeaderText)
        Write-Host ''
        Write-Host (T ' 1) 查看/检测当前版本与 Steam 环境' ' 1) Check game and Steam environment')
        Write-Host (T ' 2) 选择并下载历史版本（2.0x 列表 + 下载进度）' ' 2) Download a historical version (2.x)')
        Write-Host (T ' 3) 解锁并恢复 Steam 最新版' ' 3) Unlock and restore Steam latest')
        Write-Host (T ' 4) 锁定状态 / 开始游戏' ' 4) Lock status / launch game')
        Write-Host (T ' 5) 登记当前版本' ' 5) Register current version')
        Write-Host (T ' 6) 设置游戏目录（自动识别失败时）' ' 6) Set game directory (manual fallback)')
        Write-Host (T ' 7) 手动锁定版本' ' 7) Lock a version manually')
        Write-Host (T ' 8) Steam 文件完整性验证（临时解锁）' ' 8) Steam file integrity check (temporary unlock)')
        Write-Host (T ' 9) 解除 Steam 更新状态（恢复内置最新 ACF）' ' 9) Clear Steam update state (restore bundled latest ACF)')
        Write-Host (T ' 0) 退出' ' 0) Exit')
        Write-Host ''
        $choice = Read-Host '请选择'
        switch ($choice.Trim().ToLowerInvariant()) {
            '1' { Show-Doctor }
            '2' { $v=Show-Versions; if($v){try{$e=Get-CrimsonDesertEnvironment;$root=Select-DownloadDrive -RequiredBytes 150GB -GameDir $e.GameDir;$root=Set-DepotDownloadRoot -SteamPath $e.SteamPath -Root $root -Force:$script:DirectReplaceMode;$cmd=Get-SteamConsoleCommand $v;$content=Join-Path $root ('app_3321460\depot_3321461');$estimate=Get-EstimatedGameSize -GameDir $e.GameDir;if($estimate -gt 0){Write-StepInfo ('总体积估算依据当前游戏目录: '+(Format-Bytes -Bytes $estimate))}else{$estimate=148GB;Write-StepWarn '无法读取当前游戏大小，使用默认估算 148 GB。'};Write-Host '';Write-StepInfo ('下载内容目录: '+$content);Write-StepInfo '请在 Steam 控制台粘贴并执行以下命令:';Write-Host $cmd -ForegroundColor Yellow;if(Copy-SteamConsoleCommand $cmd){Write-StepInfo '命令已复制到剪贴板，请在 Steam 控制台按 Ctrl+V，再按 Enter。'}else{Write-StepWarn '自动复制失败，请手动复制上面的命令。'};Start-SteamConsole -SteamPath $e.SteamPath;Read-Host '确认已在 Steam 控制台按 Enter 执行命令后，回到此处按回车开始监控'|Out-Null;$wait=Wait-SteamDepotDownload -Path $content -EstimatedTotalBytes $estimate -TargetManifest $v.manifest;if($wait.CompletedPath){$content=$wait.CompletedPath;Write-StepOk ('Steam 日志确认下载完成: '+$content)};if(Test-SteamDepotDownloaded $content){Write-StepOk ('检测到下载内容: '+$content);if($e.GameDir -and ((Read-Host '是否安装并锁定此版本？(Y/N)').Trim().ToUpperInvariant() -eq 'Y')){Install-DownloadedVersion -Source $content -GameDir $e.GameDir|Out-Null;Set-VersionLock -Environment $e -Version $v;Write-StepOk '安装并锁定完成'}}else{Write-StepWarn '尚未检测到 Depot 文件，请确认 Steam 控制台命令已执行并下载完成'}}catch{Write-StepErr $_.Exception.Message}} }
            '3' { try{$e=Get-CrimsonDesertEnvironment;if($e.AcfPath){Clear-VersionLock -AcfPath $e.AcfPath;Write-StepOk '已解锁并恢复 ACF'}else{Write-StepWarn '未找到 ACF'}}catch{Write-StepErr $_.Exception.Message} }
            '4' { $s=Join-Path $script:RootDir 'state\lock.json';if(Test-Path $s){Write-StepInfo ('锁定状态: '+(Get-Content -Raw $s))}else{Write-StepInfo '当前未锁定'} }
            '5' { Show-RegisterCurrent }
            '6' { Set-GamePathManually }
            '7' { Show-ManualLock }
            '8' { try{$e=Get-CrimsonDesertEnvironment;if(!(Test-Path (Join-Path $script:RootDir 'state\lock.json'))){Write-StepWarn '当前未锁定，无需临时解锁'}elseif(!$e.AcfPath){Write-StepErr '未找到 ACF'}else{Set-LockFileWritable -AcfPath $e.AcfPath -Writable $true;Write-StepWarn 'ACF 已临时解锁。现在请在 Steam 中执行完整性验证；完成后回到此处按回车重新锁定。';Read-Host '验证完成后按回车'|Out-Null;Reapply-VersionLock -AcfPath $e.AcfPath;Write-StepOk '已重新锁定版本'}}catch{Write-StepErr $_.Exception.Message} }
            '9' { try{$e=Get-CrimsonDesertEnvironment;if(!$e.AcfPath){throw '未找到 ACF，无法解除 Steam 更新状态'};$template=Get-BundledAcfTemplate;if(!$template){throw '内置最新 ACF 模板缺失'};Restore-BundledLatestAcf -Environment $e -TemplatePath $template|Out-Null;$lockState=Join-Path $script:RootDir 'state\lock.json';if(Test-Path -LiteralPath $lockState){Remove-Item -LiteralPath $lockState -Force};Write-StepOk '已恢复内置最新 ACF，Steam 更新状态已解除';Write-StepInfo '请完全退出并重新启动 Steam，使新的 ACF 状态生效。'}catch{Write-StepErr $_.Exception.Message} }
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
        $autoEnv=Ensure-GameEnvironment
        $autoLog=Get-SteamContentLogPath -SteamPath $autoEnv.SteamPath
        if($autoEnv.AcfFound){Sync-VersionRegistryFromEnvironment -Environment $autoEnv -LogPath $autoLog|Out-Null}
        $activeTask=Find-ActiveSteamDepotDownload -SteamPath $autoEnv.SteamPath
        if($activeTask){
            $autoContent=Get-SteamDepotDownloadPath -SteamPath $autoEnv.SteamPath
            if($activeTask.CompletedPath){$autoContent=$activeTask.CompletedPath}
            Write-StepInfo ('检测到 Steam 正在下载 Depot，自动接续监控: '+$autoContent)
            Wait-SteamDepotDownload -Path $autoContent -EstimatedTotalBytes $activeTask.Total -SteamLogPath $activeTask.LogPath|Out-Null
        } else {
            $finished=Find-CompletedSteamDepotDownload -SteamPath $autoEnv.SteamPath
            if($finished){
                $configuredContent=Get-SteamDepotDownloadPath -SteamPath $autoEnv.SteamPath;$autoContent=if(Test-SteamDepotDownloaded $configuredContent){$configuredContent}elseif($finished.CompletedPath){$finished.CompletedPath}else{$configuredContent}
                if(Test-SteamDepotDownloaded $autoContent){
                    $target=Find-VersionByManifest -Manifest $finished.Manifest
                    $versionText=if($target){$target.label}else{'未知版本'};$buildText=if($target){$target.buildid}else{$finished.BuildId};$manifestText=if($target){$target.manifest}else{$finished.Manifest}
                    Write-StepOk '检测到已完成的历史版本下载'
                    Write-Host ('版本: '+$versionText+'    Build: '+$buildText+'    Manifest: '+$manifestText) -ForegroundColor Cyan
                    Write-Host ('路径: '+$autoContent) -ForegroundColor Cyan
                    if($autoEnv.GameDir -and ((Read-Host '是否现在安装并锁定已下载版本？(Y/N)').Trim().ToUpperInvariant() -eq 'Y')){
                        if(!$target){$target=[pscustomobject]@{id=('build.'+$finished.BuildId);label=('Build '+$finished.BuildId);buildid=[int64]$finished.BuildId;manifest=$finished.Manifest}}
                        Write-StepInfo '开始整目录替换，期间会显示复制进度，请勿关闭窗口。';Install-DownloadedVersion -Source $autoContent -GameDir $autoEnv.GameDir|Out-Null;Set-VersionLock -Environment $autoEnv -Version $target;Write-StepOk '安装并锁定完成';$del=(Read-Host '是否删除已下载的 Depot 文件？默认保留（Y 删除 / N 保留）').Trim().ToUpperInvariant();if($del -eq 'Y'){Remove-Item -LiteralPath (Split-Path $autoContent -Parent) -Recurse -Force;Write-StepOk '已删除下载缓存'}else{Write-StepInfo '已保留下载缓存: '+$autoContent}
                    } elseif(-not $autoEnv.GameDir){ Complete-DownloadedVersion -Environment $autoEnv -Content $autoContent -Version $target }
                }
            }
        }
    } catch { Write-StepWarn ('自动接续检查失败: '+$_.Exception.Message) }
    Show-InteractiveMenu
}
