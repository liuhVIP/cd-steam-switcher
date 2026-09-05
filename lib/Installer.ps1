# 暂存目录替换（仅覆盖同名文件，保留用户额外内容）
function Get-TreeFiles { param([string]$Root); if(Test-Path $Root){Get-ChildItem -LiteralPath $Root -Recurse -File|?{$_.FullName -notmatch '\\.DepotDownloader\\'} } }
function Install-DownloadedVersion { param([string]$Source,[string]$GameDir,[switch]$DryRun)
 if(!(Test-Path $Source)){throw '下载目录不存在'};if(!(Test-Path $GameDir)){throw '游戏目录不存在'}
 $files=@(Get-TreeFiles $Source);$plan=@($files|%{[pscustomobject]@{Source=$_.FullName;Destination=(Join-Path $GameDir ($_.FullName.Substring($Source.Length).TrimStart('\')))}})
 if($DryRun){return $plan};foreach($x in $plan){$d=Split-Path $x.Destination -Parent;if(!(Test-Path $d)){New-Item -ItemType Directory $d -Force|Out-Null};Copy-Item -LiteralPath $x.Source -Destination $x.Destination -Force};$plan
}
