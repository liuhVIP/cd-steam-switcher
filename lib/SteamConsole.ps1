# 使用官方 Steam 客户端控制台下载 Depot
#Requires -Version 3.0
function Get-StateDir { Join-Path (Split-Path -Parent $PSScriptRoot) 'state' }
function Get-SteamConsoleCommand {
 param([Parameter(Mandatory)]$Version)
 'download_depot 3321460 3321461 ' + [string]$Version.manifest
}
function Get-SteamDepotContentPath {
 param([string]$SteamPath,[string]$AppId='3321460',[string]$DepotId='3321461')
 if([string]::IsNullOrWhiteSpace($SteamPath)){return $null}
 Join-Path $SteamPath ('steamapps\content\app_'+$AppId+'\depot_'+$DepotId)
}
function Resolve-SteamPathForDepot {
 param([string]$SteamPath,[switch]$Prompt)
 if(-not [string]::IsNullOrWhiteSpace($SteamPath)){return [IO.Path]::GetFullPath($SteamPath)}
 # 环境识别偶尔会拿不到注册表 SteamPath；已创建过映射时可从 Default 入口恢复。
 try {
  $settings=Get-DepotDownloadSettingsPath
  if(Test-Path -LiteralPath $settings){
   $s=Get-Content -Raw -LiteralPath $settings|ConvertFrom-Json
   if($s.Default){
    $content=[IO.Path]::GetFullPath([string]$s.Default)
    if((Split-Path $content -Leaf) -ieq 'content'){
     $candidateRoot=Split-Path (Split-Path $content -Parent) -Parent
     if((Test-Path -LiteralPath (Join-Path $candidateRoot 'steam.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $candidateRoot 'steamapps') -PathType Container)){return $candidateRoot}
    }
   }
  }
 } catch {}
 if($Prompt){
  while($true){
   $inputPath=(Read-Host '自动识别失败，请输入 Steam 根目录（例如 D:\Steam，直接回车取消）').Trim().Trim('"')
   if([string]::IsNullOrWhiteSpace($inputPath)){return $null}
   try{$candidate=[IO.Path]::GetFullPath($inputPath)}catch{Write-StepWarn '路径格式无效，请重新输入。';continue}
   if((Test-Path -LiteralPath (Join-Path $candidate 'steam.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $candidate 'steamapps') -PathType Container)){
    return $candidate
   }
   Write-StepWarn '该目录不是有效的 Steam 根目录：需要同时存在 steam.exe 和 steamapps 文件夹。'
  }
 }
 return $null
}
function Get-SteamDepotDownloadPath {
 param([string]$SteamPath,[string]$AppId='3321460',[string]$DepotId='3321461')
 # 所有下载、监控、恢复流程统一使用 Steam 默认 content 入口。
 # app_<id> 可能是 junction，Windows 会自动解析到用户选择的目标盘。
 $resolved=Resolve-SteamPathForDepot -SteamPath $SteamPath -Prompt
 if([string]::IsNullOrWhiteSpace($resolved)){throw '无法定位 Steam 安装目录，且没有可用的下载映射记录。请先启动 Steam 后重试。'}
 Get-SteamDepotContentPath -SteamPath $resolved -AppId $AppId -DepotId $DepotId
}
function Get-DepotDownloadSettingsPath { Join-Path (Get-StateDir) 'download-settings.json' }
function Get-ConfiguredDepotRoot {
 param([string]$SteamPath)
 $p=Get-DepotDownloadSettingsPath;if(Test-Path $p){$s=Get-Content -Raw $p|ConvertFrom-Json;if($s.Root -and (Test-Path $s.Root)){return [string]$s.Root}}
 $resolved=Resolve-SteamPathForDepot -SteamPath $SteamPath -Prompt
 if([string]::IsNullOrWhiteSpace($resolved)){throw '未提供 Steam 根目录，无法定位下载目录。'}
 Join-Path $resolved 'steamapps\content'
}
function Set-DepotDownloadRoot {
 param([string]$SteamPath,[Parameter(Mandatory)][string]$Root,[switch]$Force)
 $SteamPath=Resolve-SteamPathForDepot -SteamPath $SteamPath -Prompt
 if([string]::IsNullOrWhiteSpace($SteamPath)){throw '未找到 Steam 安装目录，无法设置下载目录。请先启动 Steam 或检查 Steam 安装路径。'}
 if([string]::IsNullOrWhiteSpace($Root)){throw '下载目录为空，请重新选择有效磁盘。'}
 $default=Join-Path $SteamPath 'steamapps\content';$defaultApp=Join-Path $default 'app_3321460';$Root=[IO.Path]::GetFullPath($Root);$rootApp=Join-Path $Root 'app_3321460'
 $settings=Get-DepotDownloadSettingsPath
 if(!$Force -and (Test-Path -LiteralPath $settings)){
  try {
   $saved=Get-Content -Raw -LiteralPath $settings|ConvertFrom-Json
    if($saved.Root -and (Test-Path -LiteralPath ([string]$saved.Root) -PathType Container)){
    $savedRoot=[IO.Path]::GetFullPath([string]$saved.Root)
     if($savedRoot -ne $Root){Write-Host ('已使用现有 Depot 下载目录: '+$savedRoot) -ForegroundColor Cyan;return $savedRoot}
   }
  } catch { }
 }
 if($Root -eq [IO.Path]::GetFullPath($default)){throw '目标目录与 Steam content 目录相同'}
 if(!(Test-Path $Root)){New-Item -ItemType Directory $Root -Force|Out-Null}
 if(!(Test-Path -LiteralPath $default)){New-Item -ItemType Directory -Path $default -Force|Out-Null}
 if(Test-Path -LiteralPath $defaultApp){$item=Get-Item -LiteralPath $defaultApp -Force;$isLink=(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or ($item.LinkType -ne $null);if($isLink){Remove-Item -LiteralPath $defaultApp -Force -ErrorAction Stop}else{if(@(Get-ChildItem -LiteralPath $defaultApp -Force).Count -gt 0){throw 'Steam app_3321460 目录已有内容，请先处理后重试'};Remove-Item -LiteralPath $defaultApp -Force -ErrorAction Stop}}
 if(!(Test-Path -LiteralPath $rootApp)){New-Item -ItemType Directory -Path $rootApp -Force|Out-Null}
 New-Item -ItemType Junction -Path $defaultApp -Target $rootApp -ErrorAction Stop|Out-Null
 $d=Get-StateDir;if(!(Test-Path $d)){New-Item -ItemType Directory $d -Force|Out-Null};[pscustomobject]@{Root=$Root;Default=$default}|ConvertTo-Json|Set-Content -Encoding UTF8 (Get-DepotDownloadSettingsPath)
 $Root
}
function Get-DownloadDriveOptions {
 param([Int64]$RequiredBytes = 150GB)
 $result=@()
 foreach($d in (Get-PSDrive -PSProvider FileSystem | Sort-Object Name)){
  try{$free=[Int64]$d.Free;$result += [pscustomobject]@{Letter=([string]$d.Name).ToUpperInvariant();FreeBytes=$free;FreeText=(Format-Bytes -Bytes $free);Eligible=($free -ge $RequiredBytes)}}catch{}
 }
 $result
}
function Select-DownloadDrive {
 param([Int64]$RequiredBytes = 150GB,[string]$GameDir)
 $script:DirectReplaceMode = $false
 if([string]::IsNullOrWhiteSpace($GameDir)) {
  try { $GameDir=Get-ManualGameDirPath } catch { }
  if([string]::IsNullOrWhiteSpace($GameDir)) {
   try { $detected=Get-CrimsonDesertEnvironment; if($detected.GameDir){$GameDir=$detected.GameDir} } catch { }
  }
 }
 Write-Host '下载/安装模式：' -ForegroundColor Cyan
 Write-Host '  1) 安全模式（选择下载盘并备份）'
 Write-Host '  2) 低空间模式（使用游戏盘，不备份；失败后需重新下载）'
 $mode=(Read-Host '请选择模式（默认 1）').Trim()
 if($mode -eq '2') {
  if([string]::IsNullOrWhiteSpace($GameDir)) {
   # 没有安装过游戏时没有“游戏所在盘”可自动判断，转为无备份直装，后续由用户选择下载盘。
   Write-StepInfo '未找到现有游戏目录，低空间模式自动转为无备份直装；后续只保留一份游戏本体。'
   $mode='1'
   $script:DirectReplaceMode = $true
  } elseif(-not (Test-Path -LiteralPath $GameDir -PathType Container)) {
   Write-StepInfo '现有游戏目录不存在，低空间模式自动转为无备份直装；后续只保留一份游戏本体。'
   $mode='1'
   $script:DirectReplaceMode = $true
  } else {
   $gameRoot=[IO.Path]::GetPathRoot($GameDir);$pick=$gameRoot.TrimEnd(':\').ToUpperInvariant()
   Write-Host ('低空间模式将使用游戏所在盘: '+$gameRoot) -ForegroundColor Yellow
   Write-Host '警告：将永久删除当前游戏目录内容，释放空间后再下载；下载或安装失败后只能重新下载。' -ForegroundColor Red
   if((Read-Host '确认请输入 YES 继续').Trim() -cne 'YES'){throw '用户取消低空间模式'}
   # 只清空游戏目录内容，保留根目录本身。
   $children=@(Get-ChildItem -LiteralPath $GameDir -Force -ErrorAction Stop)
   foreach($child in $children){Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop}
   $script:DirectReplaceMode = $true
  }
 } elseif($mode -ne '' -and $mode -ne '1'){throw '模式无效，请输入 1 或 2'}
 $options=@(Get-DownloadDriveOptions -RequiredBytes $RequiredBytes)
 if(!$options.Count){throw '未检测到可用磁盘'}
 Write-Host ('需要至少 '+(Format-Bytes -Bytes $RequiredBytes)+' 可用空间（红沙完整大小约 150 GB）。') -ForegroundColor Yellow
 foreach($o in $options){$mark=if($o.Eligible){'可选'}else{'空间不足'};Write-Host (' [{0}] {1}: 可用 {2} - {3}' -f $o.Letter,$mark,$o.FreeText,$mark) -ForegroundColor $(if($o.Eligible){'Green'}else{'DarkGray'})}
 $eligible=@($options|? Eligible);if(!$eligible.Count){throw '没有可用空间达到 150 GB 的磁盘'}
 if($mode -ne '2') {
  if($mode -ne '' -and $mode -ne '1'){throw '模式无效，请输入 1 或 2'}
  $pick=(Read-Host '输入盘符（如 H；直接回车使用第一个可用盘）').Trim().TrimEnd(':').ToUpperInvariant();if(!$pick){$pick=$eligible[0].Letter}
 }
 $chosen=$options|?{$_.Letter -eq $pick}|Select-Object -First 1;if(!$chosen){throw '该盘符无效'}
 if(-not $script:DirectReplaceMode -and -not $chosen.Eligible){throw '该盘空间不足或盘符无效'}
 $root=('{0}:\CrimsonDesertDepot' -f $pick);if(!(Test-Path -LiteralPath $root)){New-Item -ItemType Directory -Path $root -Force|Out-Null};return $root
}
function Start-SteamConsole {
 param([string]$SteamPath)
 if([string]::IsNullOrWhiteSpace($SteamPath)){$SteamPath=Resolve-SteamPathForDepot -SteamPath (Get-SteamInstallPath) -Prompt}
 if(!$SteamPath){throw '未找到 Steam 安装目录'}
 $exe=Join-Path $SteamPath 'steam.exe';if(!(Test-Path $exe)){throw ('找不到 Steam: '+$exe)}
 Start-Process -FilePath $exe -ArgumentList 'steam://open/console' | Out-Null
}
function Copy-SteamConsoleCommand {
 param([Parameter(Mandatory)][string]$Command)
 try { Set-Clipboard -Value $Command; return $true } catch { return $false }
}
function Get-DirectoryBytes {
 param([string]$Path)
 if([string]::IsNullOrWhiteSpace($Path)){return [int64]0}
 if(!(Test-Path -LiteralPath $Path)){return [int64]0}
 [int64](@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)|Measure-Object Length -Sum).Sum
}
function Get-SteamContentLogPath {
 param([string]$SteamPath)
 if($SteamPath){$p=Join-Path $SteamPath 'logs\content_log.txt';if(Test-Path $p){return $p}}
}
function Get-SteamConsoleLogPath { param([string]$SteamPath);if($SteamPath){$p=Join-Path $SteamPath 'logs\console_log.txt';if(Test-Path $p){$p}} }
function Get-SteamLogDownloadStats {
 param([string]$LogPath)
 if(!(Test-Path $LogPath)){return $null}
 $lines=Get-Content -LiteralPath $LogPath -Tail 120 -ErrorAction SilentlyContinue
 $rate=0.0;$total=0L;$done=0L;$stage=0L;$stageDone=0L
 foreach($line in $lines){if($line -match 'Current download rate:\s*([\d\.]+)\s*Mbps'){$rate=[double]$Matches[1]};if($line -match 'AppID\s+3321460 update started\s*:\s*download\s+(\d+)\/(\d+),.*stage\s+(\d+)\/(\d+)'){$done=[int64]$Matches[1];$total=[int64]$Matches[2];$stageDone=[int64]$Matches[3];$stage=[int64]$Matches[4]}}
 [pscustomobject]@{RateMbps=$rate;DoneBytes=$done;TotalBytes=$total;StageDoneBytes=$stageDone;StageTotalBytes=$stage;Source=if($total -gt 0){'steam-log'}else{'estimate'}}
}
function Get-SteamLogDownloadDetails {
 param([string]$LogPath)
 if(!(Test-Path $LogPath)){return $null}
 $lines=@(Get-Content -LiteralPath $LogPath -Tail 300 -ErrorAction SilentlyContinue);$s=Get-SteamLogDownloadStats -LogPath $LogPath;$phase='';$state='';$build='';$manifest='';$errors=@();$last=$lines|Select-Object -Last 1
 foreach($line in $lines){
  if($line -match 'AppID\s+3321460 App update changed\s*:\s*(.*)$'){$phase=$Matches[1].Trim()}
  if($line -match 'AppID\s+3321460 state changed\s*:\s*(.*)$'){$state=$Matches[1].Trim()}
  if($line -match 'finished update,.*BuildID\s+(\d+).*3321461\s+\((\d+)\)'){$build=$Matches[1];$manifest=$Matches[2]}
  if($line -match 'AppID\s+3321460' -and $line -match '(?i)failed|error|access denied'){$errors+=$line}
 }
 [pscustomobject]@{Phase=$phase;State=$state;BuildId=$build;Manifest=$manifest;RateMbps=$s.RateMbps;DoneBytes=$s.DoneBytes;TotalBytes=$s.TotalBytes;StageDoneBytes=$s.StageDoneBytes;StageTotalBytes=$s.StageTotalBytes;LastLine=$last;Errors=@($errors|Select-Object -Last 5)}
}
function Find-ActiveSteamDepotDownload {
 param([string]$SteamPath)
 $steamRunning=$false
 try {$steamRunning=@(Get-Process -Name 'steam' -ErrorAction SilentlyContinue).Count -gt 0} catch {}
 if(-not $steamRunning){return $null}
 $log=Get-SteamContentLogPath -SteamPath $SteamPath;if(!$log){return $null}
  $lines=@(Get-Content -LiteralPath $log -Tail 180 -ErrorAction SilentlyContinue);$started=$null;$lastRate=$null;$lastRateTime=$null;$finish=$null
  foreach($line in $lines){
  if($line -match 'AppID\s+3321460 update started\s*:\s*download\s+(\d+)\/(\d+)'){$started=[pscustomobject]@{Done=[int64]$Matches[1];Total=[int64]$Matches[2];Line=$line}}
  if($line -match 'Current download rate:\s*([\d\.]+)\s*Mbps'){$lastRate=[double]$Matches[1];if($line -match '^\s*\[?(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}:\d{2})\]?'){try{$lastRateTime=[datetime]::Parse($Matches[1])}catch{}}}
  if($line -match 'AppID\s+3321460 finished update'){$finish=$line}
 }
  # 仅凭“update started”会把数小时/数天前的旧记录误判成当前下载。
  # Steam 日志通常带有 [yyyy-MM-dd HH:mm:ss] 时间戳；同时要求 downloading
  # 临时目录存在且近期有写入，避免 Steam 开着但下载已经结束时进入监听。
  if($started){
   $recent=$false
   # 最新速率必须大于 0；仅历史上出现过正速率不能证明当前仍在下载。
   if($lastRate -gt 0 -and $lastRateTime){$recent=((Get-Date)-$lastRateTime).TotalMinutes -le 2}
   # Steam 的实际写入入口固定是默认 content 目录；这里即使 app_3321460
   # 是 junction，也会正确跟随到用户选择的下载盘。配置目录仅作为备用。
   $downloadDirs=@()
   $defaultDepot=Get-SteamDepotDownloadPath -SteamPath $SteamPath
   if($defaultDepot){$downloadDirs+=$defaultDepot}
   try{$configuredDepot=Join-Path (Get-ConfiguredDepotRoot -SteamPath $SteamPath) 'app_3321460\depot_3321461';if($downloadDirs -notcontains $configuredDepot){$downloadDirs+=$configuredDepot}}catch{}
   $recentFiles=$false
   foreach($downloadDir in $downloadDirs){
    if(Test-Path -LiteralPath $downloadDir -PathType Container){
     try{if(@(Get-ChildItem -LiteralPath $downloadDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {((Get-Date)-$_.LastWriteTime).TotalSeconds -le 60}).Count -gt 0){$recentFiles=$true;break}}catch{}
    }
   }
   # 只有近期正速率或近期写入文件才认为确实仍在下载。
   if(!$recent -and !$recentFiles){$started=$null}
  }
  $manual=$false;$console=Get-SteamConsoleLogPath -SteamPath $SteamPath;if($console){$manual=@(Get-Content $console -Tail 120|?{$_ -match 'download_depot\s+3321460\s+3321461'}).Count -gt 0}
  # Steam may not write the console command itself; an unfinished depot-style
  # update record is sufficient to resume monitoring after a restart.
  if($started -and (!$finish -or $lines.IndexOf($started.Line) -gt $lines.IndexOf($finish))){$started|Add-Member NoteProperty LogPath $log;$started|Add-Member NoteProperty RateMbps $lastRate;$started}
}
function Find-CompletedSteamDepotDownload {
 param([string]$SteamPath)
 $console=Get-SteamConsoleLogPath -SteamPath $SteamPath;$log=Get-SteamContentLogPath -SteamPath $SteamPath;if($console){$cl=Get-Content -LiteralPath $console -Tail 300 -ErrorAction SilentlyContinue;$complete=$cl|?{$_ -match 'Depot download complete\s*:\s*"([^"]+)"\s*\(manifest\s+(\d+)\)'}|Select-Object -Last 1;if($complete -and $complete -match 'Depot download complete\s*:\s*"([^"]+)"\s*\(manifest\s+(\d+)\)'){return [pscustomobject]@{BuildId='';Manifest=$Matches[2];LogPath=$console;CompletedPath=$Matches[1]}}};if(!$log){return $null}
 $all=@(Get-Content -LiteralPath $log -Tail 600 -ErrorAction SilentlyContinue);$lastStart=($all|Select-String 'AppID\s+3321460 update started'|Select-Object -Last 1);$lastFinish=($all|Select-String 'AppID\s+3321460 finished update'|Select-Object -Last 1);$line=$null;if($lastFinish -and (!$lastStart -or [string]$lastFinish.LineNumber -gt [string]$lastStart.LineNumber)){$line=$lastFinish.Line}
 if($line -and $line -match 'BuildID\s+(\d+).*3321461\s+\((\d+)\)'){[pscustomobject]@{BuildId=$Matches[1];Manifest=$Matches[2];LogPath=$log}}
 if(!$line){$start=($all|?{$_ -match 'AppID\s+3321460 update started\s*:\s*download\s+(\d+)\/(\d+).*stage\s+(\d+)\/(\d+)'}|Select-Object -Last 1);if($start -and $start -match 'download\s+(\d+)\/(\d+).*stage\s+(\d+)\/(\d+)'){$content=Get-SteamDepotDownloadPath -SteamPath $SteamPath;$size=Get-DirectoryBytes $content;if($size -ge [int64]$Matches[4]){[pscustomobject]@{BuildId='';Manifest='';LogPath=$log;StageTotal=[int64]$Matches[4]}}}}
}
function Get-EstimatedGameSize {
 param([string]$GameDir)
 $bytes=Get-DirectoryBytes $GameDir
 if($bytes -gt 1GB){return $bytes}
 return [Int64]0
}
function Test-SteamDepotDownloaded {
 param([string]$Path)
 if(!(Test-Path $Path)){return $false}
 return (@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0)
}
function Find-CompletedDepotPath {
 param([string]$SteamPath,[string]$FallbackPath)
 if($FallbackPath -and (Test-SteamDepotDownloaded $FallbackPath)){return $FallbackPath}
 $console=Get-SteamConsoleLogPath -SteamPath $SteamPath
 if($console){$line=Get-Content -LiteralPath $console -Tail 300 -ErrorAction SilentlyContinue|Where-Object{$_ -match 'Depot download complete\s*:\s*"([^"]+)"\s*\(manifest'}|Select-Object -Last 1;if($line -and $line -match 'Depot download complete\s*:\s*"([^"]+)"'){ $p=Join-Path $Matches[1] 'depot_3321461';if(Test-SteamDepotDownloaded $p){return $p} }}
 return $FallbackPath
}
function Get-SteamDepotResumeInfo {
 param([string]$Path)
 [pscustomobject]@{Exists=(Test-Path $Path);Files=if(Test-Path $Path){@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count}else{0};Bytes=(Get-DirectoryBytes $Path)}
}
function Wait-SteamDepotDownload {
 param([Parameter(Mandatory)][string]$Path,[Int64]$EstimatedTotalBytes = 148GB,[string]$SteamLogPath,[string]$TargetManifest)
 if([string]::IsNullOrWhiteSpace($SteamLogPath)){try{$SteamLogPath=Get-SteamContentLogPath -SteamPath (Get-SteamInstallPath)}catch{}}
  $start=Get-Date;$lastBytes=[int64]0;$lastTime=Get-Date;$emptyTicks=0;$history=New-Object System.Collections.Generic.Queue[object];$consoleLogPath=Get-SteamConsoleLogPath -SteamPath (Get-SteamInstallPath);$completedPath=$null;$completedManifest=$null;$initialConsoleLines=@();if($consoleLogPath -and (Test-Path -LiteralPath $consoleLogPath)){$initialConsoleLines=@(Get-Content -LiteralPath $consoleLogPath -Tail 120 -ErrorAction SilentlyContinue)}
 Write-Host '正在监控 Steam 下载；Steam 控制台会显示官方状态，工具窗口显示本地写入进度。' -ForegroundColor Cyan
 Write-Host '下载完成后请回到本窗口按回车继续。' -ForegroundColor Yellow
  while($true){
   try { if(@(Get-Process -Name 'steam' -ErrorAction SilentlyContinue).Count -eq 0){Write-Host '';Write-StepWarn 'Steam 已退出，停止下载监控。';break} } catch { }
   try { if([Console]::KeyAvailable){$k=[Console]::ReadKey($true);if($k.Key -eq 'Enter'){break}} } catch { }
  $now=Get-Date;$bytes=[Int64](Get-DirectoryBytes $Path);$files=if(Test-Path $Path){@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count}else{0};$history.Enqueue([pscustomobject]@{Time=$now;Bytes=$bytes});while($history.Count -gt 1 -and (($now-$history.Peek().Time).TotalSeconds -gt 15)){$history.Dequeue()|Out-Null};$base=$history.Peek();$seconds=[Math]::Max(1,($now-$base.Time).TotalSeconds);$rate=[Int64](($bytes-$base.Bytes)/$seconds);$elapsed=($now-$start).ToString('hh\:mm\:ss');$estimate=$EstimatedTotalBytes;$percent=if($estimate -gt 0){[Math]::Min(99,[Math]::Max(0,($bytes/$estimate*100)))}else{0};$steam=if($SteamLogPath){Get-SteamLogDownloadStats $SteamLogPath};if($steam -and $steam.TotalBytes -gt 0){$estimate=$steam.TotalBytes;$effectiveDone=[Math]::Max([Int64]$bytes,[Int64]$steam.DoneBytes);$percent=[Math]::Min(99,($effectiveDone/$estimate*100));if($steam.RateMbps -gt 0){$rate=[Int64]($steam.RateMbps*1000000/8)}}
   $doneLine=$null
   if($consoleLogPath -and (Test-Path -LiteralPath $consoleLogPath)){$consoleTail=@(Get-Content -LiteralPath $consoleLogPath -Tail 120 -ErrorAction SilentlyContinue);$newLines=@($consoleTail|Where-Object{ $initialConsoleLines -notcontains $_ });$doneLine=$newLines|Where-Object{$_ -match 'Depot download complete\s*:\s*"([^"]+)"\s*\(manifest\s+(\d+)\)' -and (!$TargetManifest -or $_ -match [regex]::Escape($TargetManifest))}|Select-Object -Last 1;if($doneLine -and $doneLine -match 'Depot download complete\s*:\s*"([^"]+)"\s*\(manifest\s+(\d+)\)'){$completedPath=$Matches[1];$completedManifest=$Matches[2];$percent=100;$rate=0}}
   if(-not $doneLine -and $SteamLogPath -and (Test-Path $SteamLogPath)){$tail=Get-Content -LiteralPath $SteamLogPath -Tail 80 -ErrorAction SilentlyContinue;$doneLine=$tail|Where-Object{$_ -match 'AppID\s+3321460 finished update' -and (!$TargetManifest -or $_ -match [regex]::Escape($TargetManifest))}|Select-Object -Last 1;if($doneLine){$percent=100;$rate=0}}
  $tag=if($steam -and $steam.TotalBytes -gt 0){'Steam总量+本地进度'}else{'估算'};Write-Progress -Activity ('Steam 官方下载（'+$tag+'）') -Status (('{0}  {1:N1}%  已下载 {2} / {3}  速度 {4}/s  文件 {5}' -f $elapsed,$percent,(Format-Bytes -Bytes $bytes),(Format-Bytes -Bytes $estimate),(Format-Bytes -Bytes $rate),$files)) -PercentComplete $percent
  if($doneLine){break};if($bytes -eq 0){$emptyTicks++;if($emptyTicks -eq 15){Write-Host '';Write-StepWarn '30 秒内未检测到文件：请确认 Steam 控制台已粘贴命令并按 Enter 执行。'}}else{$emptyTicks=0};$lastBytes=$bytes;$lastTime=$now;Start-Sleep -Seconds 2
 }
 Write-Progress -Activity 'Steam 官方下载' -Completed
  return [pscustomobject]@{Bytes=(Get-DirectoryBytes $Path);Files=if(Test-Path $Path){@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count}else{0};Elapsed=(Get-Date)-$start;CompletedPath=$completedPath;Manifest=$completedManifest}
}
