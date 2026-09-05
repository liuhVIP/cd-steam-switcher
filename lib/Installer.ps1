# 暂存目录替换（仅覆盖同名文件，保留用户额外内容）
function Get-TreeFiles { param([string]$Root); if(Test-Path $Root){Get-ChildItem -LiteralPath $Root -Recurse -File|?{$_.FullName -notmatch '\\.DepotDownloader\\'} } }
function Install-DownloadedVersion { param([string]$Source,[string]$GameDir,[switch]$DryRun)
 if(!(Test-Path $Source)){throw '下载目录不存在'};if(!(Test-Path $GameDir)){throw '游戏目录不存在'}
 $files=@(Get-TreeFiles $Source);$plan=@($files|%{[pscustomobject]@{Source=$_.FullName;Destination=(Join-Path $GameDir ($_.FullName.Substring($Source.Length).TrimStart('\')))}})
 if($DryRun){return $plan};$total=[Int64](($files|Measure-Object Length -Sum).Sum);$done=[Int64]0;$index=0;$start=Get-Date
 foreach($x in $plan){$d=Split-Path $x.Destination -Parent;if(!(Test-Path $d)){New-Item -ItemType Directory $d -Force|Out-Null};Copy-Item -LiteralPath $x.Source -Destination $x.Destination -Force;$done+=[Int64]((Get-Item -LiteralPath $x.Source).Length);$index++;$pct=if($total -gt 0){[Math]::Min(100,$done/$total*100)}else{100};$elapsed=[Math]::Max(1,((Get-Date)-$start).TotalSeconds);$rate=[Int64]($done/$elapsed);Write-Progress -Activity '安装历史版本' -Status ('{0:N1}%  {1}/{2} 文件  已复制 {3}/{4}  速度 {5}/s' -f $pct,$index,$files.Count,(Format-Bytes -Bytes $done),(Format-Bytes -Bytes $total),(Format-Bytes -Bytes $rate)) -PercentComplete $pct}
 Write-Progress -Activity '安装历史版本' -Completed;$plan
}
