# 使用官方 Steam 客户端控制台下载 Depot
#Requires -Version 3.0
function Get-SteamConsoleCommand {
 param([Parameter(Mandatory)]$Version)
 'download_depot 3321460 3321461 ' + [string]$Version.manifest
}
function Get-SteamDepotContentPath {
 param([string]$SteamPath,[string]$AppId='3321460',[string]$DepotId='3321461')
 if([string]::IsNullOrWhiteSpace($SteamPath)){return $null}
 Join-Path $SteamPath ('steamapps\content\app_'+$AppId+'\depot_'+$DepotId)
}
function Get-DepotDownloadSettingsPath { Join-Path (Get-StateDir) 'download-settings.json' }
function Get-ConfiguredDepotRoot {
 param([string]$SteamPath)
 $p=Get-DepotDownloadSettingsPath;if(Test-Path $p){$s=Get-Content -Raw $p|ConvertFrom-Json;if($s.Root -and (Test-Path $s.Root)){return [string]$s.Root}}
 Join-Path $SteamPath 'steamapps\content'
}
function Set-DepotDownloadRoot {
 param([Parameter(Mandatory)][string]$SteamPath,[Parameter(Mandatory)][string]$Root)
 $default=Join-Path $SteamPath 'steamapps\content';$Root=[IO.Path]::GetFullPath($Root)
 if($Root -eq [IO.Path]::GetFullPath($default)){throw '目标目录与默认目录相同'}
 if(!(Test-Path $Root)){New-Item -ItemType Directory $Root -Force|Out-Null}
 if(Test-Path $default){$item=Get-Item -LiteralPath $default -Force;if($item.LinkType){Remove-Item $default -Force}else{if(@(Get-ChildItem $default -Force).Count -gt 0){throw 'Steam 默认 content 目录非空，无法安全迁移'};Remove-Item $default -Force}}
 New-Item -ItemType Junction -Path $default -Target $Root -ErrorAction Stop|Out-Null
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
 param([Int64]$RequiredBytes = 150GB)
 $options=@(Get-DownloadDriveOptions -RequiredBytes $RequiredBytes)
 if(!$options.Count){throw '未检测到可用磁盘'}
 Write-Host ('需要至少 '+(Format-Bytes -Bytes $RequiredBytes)+' 可用空间（红沙完整大小约 150 GB）。') -ForegroundColor Yellow
 foreach($o in $options){$mark=if($o.Eligible){'可选'}else{'空间不足'};Write-Host (' [{0}] {1}: 可用 {2} - {3}' -f $o.Letter,$mark,$o.FreeText,$mark) -ForegroundColor $(if($o.Eligible){'Green'}else{'DarkGray'})}
 $eligible=@($options|? Eligible);if(!$eligible.Count){throw '没有可用空间达到 150 GB 的磁盘'}
 $pick=(Read-Host '输入盘符（如 H；直接回车使用第一个可用盘）').Trim().TrimEnd(':').ToUpperInvariant();if(!$pick){$pick=$eligible[0].Letter}
 $chosen=$eligible|?{$_.Letter -eq $pick}|Select-Object -First 1;if(!$chosen){throw '该盘空间不足或盘符无效'}
 $root=$pick+':\CrimsonDesertDepot';if(!(Test-Path $root)){New-Item -ItemType Directory $root -Force|Out-Null};$root
}
function Start-SteamConsole {
 param([string]$SteamPath)
 if([string]::IsNullOrWhiteSpace($SteamPath)){$SteamPath=Get-SteamInstallPath}
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
 if(!(Test-Path $Path)){return [int64]0}
 [int64](@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)|Measure-Object Length -Sum).Sum
}
function Get-SteamContentLogPath {
 param([string]$SteamPath)
 if($SteamPath){$p=Join-Path $SteamPath 'logs\content_log.txt';if(Test-Path $p){return $p}}
}
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
 $log=Get-SteamContentLogPath -SteamPath $SteamPath;if(!$log){return $null}
 $lines=@(Get-Content -LiteralPath $log -Tail 180 -ErrorAction SilentlyContinue);$started=$null;$lastRate=$null
 foreach($line in $lines){
  if($line -match 'AppID\s+3321460 update started\s*:\s*download\s+(\d+)\/(\d+)'){$started=[pscustomobject]@{Done=[int64]$Matches[1];Total=[int64]$Matches[2];Line=$line}}
  if($line -match 'Current download rate:\s*([\d\.]+)\s*Mbps'){$lastRate=[double]$Matches[1]}
 }
 if($started -and $lastRate -gt 0){$started|Add-Member NoteProperty LogPath $log;$started|Add-Member NoteProperty RateMbps $lastRate;$started}
}
function Find-CompletedSteamDepotDownload {
 param([string]$SteamPath)
 $log=Get-SteamContentLogPath -SteamPath $SteamPath;if(!$log){return $null}
 $line=(Get-Content -LiteralPath $log -Tail 400 -ErrorAction SilentlyContinue|?{$_ -match 'AppID\s+3321460 finished update,.*BuildID\s+(\d+).*3321461\s+\((\d+)\)' }|Select-Object -Last 1)
 if($line -and $line -match 'BuildID\s+(\d+).*3321461\s+\((\d+)\)'){[pscustomobject]@{BuildId=$Matches[1];Manifest=$Matches[2];LogPath=$log}}
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
function Get-SteamDepotResumeInfo {
 param([string]$Path)
 [pscustomobject]@{Exists=(Test-Path $Path);Files=if(Test-Path $Path){@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count}else{0};Bytes=(Get-DirectoryBytes $Path)}
}
function Wait-SteamDepotDownload {
 param([Parameter(Mandatory)][string]$Path,[Int64]$EstimatedTotalBytes = 148GB,[string]$SteamLogPath,[string]$TargetManifest)
 if([string]::IsNullOrWhiteSpace($SteamLogPath)){try{$SteamLogPath=Get-SteamContentLogPath -SteamPath (Get-SteamInstallPath)}catch{}}
 $start=Get-Date;$lastBytes=[int64]0;$lastTime=Get-Date;$emptyTicks=0;$history=New-Object System.Collections.Generic.Queue[object]
 Write-Host '正在监控 Steam 下载；Steam 控制台会显示官方状态，工具窗口显示本地写入进度。' -ForegroundColor Cyan
 Write-Host '下载完成后请回到本窗口按回车继续。' -ForegroundColor Yellow
 while($true){
  try { if([Console]::KeyAvailable){$k=[Console]::ReadKey($true);if($k.Key -eq 'Enter'){break}} } catch { }
  $now=Get-Date;$bytes=[Int64](Get-DirectoryBytes $Path);$files=if(Test-Path $Path){@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count}else{0};$history.Enqueue([pscustomobject]@{Time=$now;Bytes=$bytes});while($history.Count -gt 1 -and (($now-$history.Peek().Time).TotalSeconds -gt 15)){$history.Dequeue()|Out-Null};$base=$history.Peek();$seconds=[Math]::Max(1,($now-$base.Time).TotalSeconds);$rate=[Int64](($bytes-$base.Bytes)/$seconds);$elapsed=($now-$start).ToString('hh\:mm\:ss');$estimate=$EstimatedTotalBytes;$percent=if($estimate -gt 0){[Math]::Min(99,[Math]::Max(0,($bytes/$estimate*100)))}else{0};$steam=if($SteamLogPath){Get-SteamLogDownloadStats $SteamLogPath};if($steam -and $steam.TotalBytes -gt 0){$estimate=$steam.TotalBytes;$effectiveDone=[Math]::Max([Int64]$bytes,[Int64]$steam.DoneBytes);$percent=[Math]::Min(99,($effectiveDone/$estimate*100));if($steam.RateMbps -gt 0){$rate=[Int64]($steam.RateMbps*1000000/8)}}
  if($SteamLogPath -and (Test-Path $SteamLogPath)){$tail=Get-Content -LiteralPath $SteamLogPath -Tail 80 -ErrorAction SilentlyContinue;$doneLine=$tail|Where-Object{$_ -match 'AppID\s+3321460 finished update' -and (!$TargetManifest -or $_ -match [regex]::Escape($TargetManifest))}|Select-Object -Last 1;if($doneLine){$percent=100;$rate=0}}
  $tag=if($steam -and $steam.TotalBytes -gt 0){'Steam总量+本地进度'}else{'估算'};Write-Progress -Activity ('Steam 官方下载（'+$tag+'）') -Status (('{0}  {1:N1}%  已下载 {2} / {3}  速度 {4}/s  文件 {5}' -f $elapsed,$percent,(Format-Bytes -Bytes $bytes),(Format-Bytes -Bytes $estimate),(Format-Bytes -Bytes $rate),$files)) -PercentComplete $percent
  if($doneLine){break};if($bytes -eq 0){$emptyTicks++;if($emptyTicks -eq 15){Write-Host '';Write-StepWarn '30 秒内未检测到文件：请确认 Steam 控制台已粘贴命令并按 Enter 执行。'}}else{$emptyTicks=0};$lastBytes=$bytes;$lastTime=$now;Start-Sleep -Seconds 2
 }
 Write-Progress -Activity 'Steam 官方下载' -Completed
 return [pscustomobject]@{Bytes=(Get-DirectoryBytes $Path);Files=if(Test-Path $Path){@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count}else{0};Elapsed=(Get-Date)-$start}
}
