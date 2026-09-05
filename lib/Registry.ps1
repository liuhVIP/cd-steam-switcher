# 版本登记表
#Requires -Version 3.0
function Get-VersionsFilePath { Join-Path (Split-Path -Parent $PSScriptRoot) 'versions.json' }
function Compare-GameVersion {
 param([string]$A,[string]$B)
 $aa=@($A -split '\.'|%{[int]($_ -replace '\D.*','')}); $bb=@($B -split '\.'|%{[int]($_ -replace '\D.*','')});
 for($i=0;$i -lt [Math]::Max($aa.Count,$bb.Count);$i++){ $x=if($i -lt $aa.Count){$aa[$i]}else{0};$y=if($i -lt $bb.Count){$bb[$i]}else{0}; if($x -ne $y){return [Math]::Sign($x-$y)} }; return 0
}
function Test-VersionScope { param([string]$Version);if($Version -notmatch '^(\d+)\.(\d+)(?:\.(\d+))?$'){return $false};$major=[int]$Matches[1];$minor=[int]$Matches[2];return (($major -eq 1 -and $minor -ge 14) -or $major -ge 2) }
function Read-VersionRegistry { param([string]$Path=(Get-VersionsFilePath)); if(!(Test-Path $Path)){throw "找不到版本登记表: $Path"}; $utf8=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::ReadAllText($Path,$utf8)|ConvertFrom-Json }
function Save-VersionRegistry { param($Registry,[string]$Path=(Get-VersionsFilePath)); $dir=Split-Path $Path -Parent;if(!(Test-Path $dir)){New-Item -ItemType Directory $dir -Force|Out-Null}; $utf8=New-Object System.Text.UTF8Encoding($true); [IO.File]::WriteAllText($Path,($Registry|ConvertTo-Json -Depth 8),$utf8) }
function Merge-VersionRegistryFile {
 param([Parameter(Mandatory)][string]$UpdatePath,[string]$Path=(Get-VersionsFilePath))
 if(!(Test-Path $UpdatePath)){throw "找不到更新 JSON: $UpdatePath"}
 $base=Read-VersionRegistry $Path;$update=Get-Content -Raw -LiteralPath $UpdatePath|ConvertFrom-Json;$items=@($base.versions)
 foreach($entry in @($update.versions)){
  if(!$entry.manifest -or !$entry.buildid){continue}
  $same=@($items|?{[string]$_.manifest -eq [string]$entry.manifest -or [string]$_.buildid -eq [string]$entry.buildid})
  if($same.Count -eq 0){$items+=$entry}else{$items[$items.IndexOf($same[0])]=$entry}
 }
 $base.versions=$items;Save-VersionRegistry $base $Path;return $base
}
function Get-VersionList { param([string]$Path=(Get-VersionsFilePath)); $r=Read-VersionRegistry $Path; $items=@($r.versions|?{(Test-VersionScope $_.id) -or ([string]$_.id -like 'build.*')}); $items|Sort-Object @{e={[int64]$_.buildid};Descending=$true} }
function Find-VersionByManifest { param([string]$Manifest,[string]$Path=(Get-VersionsFilePath)); @(Read-VersionRegistry $Path).versions|?{[string]$_.manifest -eq $Manifest}|Select-Object -First 1 }
function Find-VersionByBuild { param([string]$BuildId,[string]$Path=(Get-VersionsFilePath)); @(Read-VersionRegistry $Path).versions|?{[string]$_.buildid -eq $BuildId}|Select-Object -First 1 }
function Register-VersionEntry {
 param([Parameter(Mandatory)]$Entry,[string]$Path=(Get-VersionsFilePath))
 if(!(Test-VersionScope $Entry.id)){throw '仅允许登记 2.x 版本'}; if($Entry.id -notmatch '^\d+\.\d+\.\d+$'){throw '版本号必须为 x.yy.zz'}
 $r=Read-VersionRegistry $Path; $old=@($r.versions)|?{$_.id -eq $Entry.id -or ([string]$_.manifest -eq [string]$Entry.manifest)}; if($old){return $old[0]}; $r.versions=@($r.versions)+$Entry; Save-VersionRegistry $r $Path; return $Entry
}
function Sync-VersionRegistryFromEnvironment {
 param([Parameter(Mandatory)]$Environment,[string]$Path=(Get-VersionsFilePath),[string]$LogPath)
 $r=Read-VersionRegistry $Path;$changed=$false;$items=@($r.versions)
 $pairs=@()
 if($Environment.BuildId -and $Environment.DepotManifest){$pairs+=[pscustomobject]@{Build=[string]$Environment.BuildId;Manifest=[string]$Environment.DepotManifest}}
 if($LogPath -and (Test-Path $LogPath)){foreach($line in (Get-Content $LogPath -Tail 2000)){if($line -match 'AppID\s+3321460 finished update,.*BuildID\s+(\d+).*3321461\s+\((\d+)\)'){$pairs+=[pscustomobject]@{Build=$Matches[1];Manifest=$Matches[2]}}}}
 foreach($p in ($pairs|Sort-Object Build -Unique)){
  $found=@($items|?{[string]$_.manifest -eq $p.Manifest -or [string]$_.buildid -eq $p.Build});if($found.Count -eq 0){$items+= [pscustomobject]@{id=('build.'+$p.Build);label=('Build '+$p.Build);release_date=(Get-Date -Format yyyy-MM-dd);buildid=[int64]$p.Build;manifest=$p.Manifest;exe_sha256='';notes='从 Steam content_log 自动发现；版本名称待补充';source='steam-log';verified=$true};$changed=$true}
 }
 if($changed){$r.versions=$items;Save-VersionRegistry $r $Path};return $changed
}
