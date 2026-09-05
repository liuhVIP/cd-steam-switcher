# 整目录替换安装
function Get-TreeFiles { param([string]$Root); if([string]::IsNullOrWhiteSpace($Root)){return @()}; if(Test-Path -LiteralPath $Root){Get-ChildItem -LiteralPath $Root -Recurse -File} }

function Install-DownloadedVersion {
 param([string]$Source,[string]$GameDir,[switch]$DryRun,[switch]$DirectReplace)
 if(!(Test-Path -LiteralPath $Source -PathType Container)){throw '下载目录不存在'}
 if($DryRun){return @(Get-TreeFiles $Source)}
 if(-not $DirectReplace -and (Get-Variable -Name DirectReplaceMode -Scope Script -ErrorAction SilentlyContinue)){$DirectReplace=[bool]$script:DirectReplaceMode}
 # 目标游戏不存在时没有备份对象：同盘直接移动文件，避免为安全模式额外占用一份完整游戏空间。
 # 若目标已存在，则仍按安全模式保留备份并复制；低空间模式由 DirectReplace 强制移动。
 $targetExists=Test-Path -LiteralPath $GameDir -PathType Container
 if(-not $targetExists){
  # 无旧游戏时直接采用移动策略；同盘是真正的零额外空间移动，跨盘由系统执行移动所需的转移。
  $DirectReplace=$true
 }
 $files=@(Get-TreeFiles $Source);$total=[Int64](($files|Measure-Object Length -Sum).Sum)
 $drive=[IO.Path]::GetPathRoot($GameDir);$free=[IO.DriveInfo]::new($drive).AvailableFreeSpace;$moved=$false
 $parent=Split-Path $GameDir -Parent;$backup=Join-Path $parent ((Split-Path $GameDir -Leaf)+'.backup_'+(Get-Date -Format yyyyMMdd_HHmmss))
 if((Test-Path -LiteralPath $GameDir) -and $free -lt $total){Write-Host ('磁盘剩余 '+(Format-Bytes -Bytes $free)+'，安装至少需要 '+(Format-Bytes -Bytes $total)+'。') -ForegroundColor Yellow;$answer=Read-Host '空间不足，是否删除现有游戏目录后继续？(Y/N，默认 N)';if($null -eq $answer){$answer='N'}else{$answer=$answer.Trim().ToUpperInvariant()};if($answer -ne 'Y'){throw '空间不足，用户取消安装'};Remove-Item -LiteralPath $GameDir -Recurse -Force}
 try {
  if(Test-Path -LiteralPath $GameDir){if($DirectReplace){$existing=@(Get-ChildItem -LiteralPath $GameDir -Force);foreach($item in $existing){Remove-Item -LiteralPath $item.FullName -Recurse -Force}}else{Move-Item -LiteralPath $GameDir -Destination $backup;$moved=$true}}
  New-Item -ItemType Directory -Path $GameDir -Force|Out-Null;$done=0L;$i=0;$start=Get-Date
  foreach($f in $files){$rel=$f.FullName.Substring($Source.Length).TrimStart('\');$dest=Join-Path $GameDir $rel;$d=Split-Path $dest -Parent;if(!(Test-Path -LiteralPath $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null};if($DirectReplace){Move-Item -LiteralPath $f.FullName -Destination $dest -Force}else{Copy-Item -LiteralPath $f.FullName -Destination $dest -Force};$done+=$f.Length;$i++;$pct=if($total){$done/$total*100}else{100};$rate=[Int64]($done/[Math]::Max(1,((Get-Date)-$start).TotalSeconds));Write-Progress -Activity $(if($DirectReplace){'移动游戏文件'}else{'替换游戏目录'}) -Status ('{0:N1}% {1}/{2} 文件 {3}/{4} {5}/s' -f $pct,$i,$files.Count,(Format-Bytes -Bytes $done),(Format-Bytes -Bytes $total),(Format-Bytes -Bytes $rate)) -PercentComplete $pct}
  Write-Progress -Activity '替换游戏目录' -Completed;if($moved){Remove-Item -LiteralPath $backup -Recurse -Force};Write-Host '安装完成，下载缓存默认保留。' -ForegroundColor Green
  $remove=Read-Host '是否删除下载缓存？(Y/N，默认 N)';if($null -eq $remove){$remove='N'}else{$remove=$remove.Trim().ToUpperInvariant()};if($remove -eq 'Y'){Remove-Item -LiteralPath $Source -Recurse -Force;Write-Host '已删除下载缓存。' -ForegroundColor Green}else{Write-Host ('已保留下载缓存: '+$Source) -ForegroundColor Cyan}
  [pscustomobject]@{Success=$true;Destination=$GameDir;Files=$files.Count;DirectReplace=$DirectReplace}
 } catch {
  if(Test-Path -LiteralPath $GameDir){Remove-Item -LiteralPath $GameDir -Recurse -Force -ErrorAction SilentlyContinue}
  if($moved -and (Test-Path -LiteralPath $backup)){Move-Item -LiteralPath $backup -Destination $GameDir -Force}
  if($_.Exception.Message -match '(?i)being used by another process|另一个进程|access.*denied|拒绝访问'){
   throw '安装失败：Steam 仍在占用下载文件。请确认 Steam 控制台已显示下载完成，关闭 Steam 下载/控制台（必要时完全退出 Steam）后，再重新执行安装。'
  }
  throw
 }
}
