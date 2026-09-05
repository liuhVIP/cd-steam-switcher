# 版本登记表
#Requires -Version 3.0
function Get-VersionsFilePath { Join-Path (Split-Path -Parent $PSScriptRoot) 'versions.json' }
function Compare-GameVersion {
 param([string]$A,[string]$B)
 $aa=@($A -split '\.'|%{[int]($_ -replace '\D.*','')}); $bb=@($B -split '\.'|%{[int]($_ -replace '\D.*','')});
 for($i=0;$i -lt [Math]::Max($aa.Count,$bb.Count);$i++){ $x=if($i -lt $aa.Count){$aa[$i]}else{0};$y=if($i -lt $bb.Count){$bb[$i]}else{0}; if($x -ne $y){return [Math]::Sign($x-$y)} }; return 0
}
function Test-VersionScope { param([string]$Version) return ($Version -match '^2(?:\.\d+){1,3}$') }
function Read-VersionRegistry { param([string]$Path=(Get-VersionsFilePath)); if(!(Test-Path $Path)){throw "找不到版本登记表: $Path"}; $utf8=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::ReadAllText($Path,$utf8)|ConvertFrom-Json }
function Save-VersionRegistry { param($Registry,[string]$Path=(Get-VersionsFilePath)); $dir=Split-Path $Path -Parent;if(!(Test-Path $dir)){New-Item -ItemType Directory $dir -Force|Out-Null}; $utf8=New-Object System.Text.UTF8Encoding($true); [IO.File]::WriteAllText($Path,($Registry|ConvertTo-Json -Depth 8),$utf8) }
function Get-VersionList { param([string]$Path=(Get-VersionsFilePath)); $r=Read-VersionRegistry $Path; $items=@($r.versions|?{Test-VersionScope $_.id}); for($i=0;$i -lt $items.Count;$i++){for($j=$i+1;$j -lt $items.Count;$j++){if((Compare-GameVersion ([string]$items[$i].id) ([string]$items[$j].id)) -lt 0){$t=$items[$i];$items[$i]=$items[$j];$items[$j]=$t}}}; $items }
function Find-VersionByManifest { param([string]$Manifest,[string]$Path=(Get-VersionsFilePath)); @(Read-VersionRegistry $Path).versions|?{[string]$_.manifest -eq $Manifest}|Select-Object -First 1 }
function Find-VersionByBuild { param([string]$BuildId,[string]$Path=(Get-VersionsFilePath)); @(Read-VersionRegistry $Path).versions|?{[string]$_.buildid -eq $BuildId}|Select-Object -First 1 }
function Register-VersionEntry {
 param([Parameter(Mandatory)]$Entry,[string]$Path=(Get-VersionsFilePath))
 if(!(Test-VersionScope $Entry.id)){throw '仅允许登记 2.x 版本'}; if($Entry.id -notmatch '^\d+\.\d+\.\d+$'){throw '版本号必须为 x.yy.zz'}
 $r=Read-VersionRegistry $Path; $old=@($r.versions)|?{$_.id -eq $Entry.id -or ([string]$_.manifest -eq [string]$Entry.manifest)}; if($old){return $old[0]}; $r.versions=@($r.versions)+$Entry; Save-VersionRegistry $r $Path; return $Entry
}
