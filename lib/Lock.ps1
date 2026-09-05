# ACF 锁定/解锁（写前备份，操作可逆）
function Set-VersionLock { param([Parameter(Mandatory)]$Environment,[Parameter(Mandatory)]$Version)
 if(!$Environment.AcfPath){throw '未找到 ACF'}; $backup=Join-Path (Get-StateDir) ('acf_backup_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.acf');Copy-FileBackup $Environment.AcfPath $backup -Force
 $n=Read-VdfFile $Environment.AcfPath;Set-AcfBuildId $n ([string]$Version.buildid);Set-AcfDepotManifest $n '3321461' ([string]$Version.manifest);Set-FileReadOnly $Environment.AcfPath $false;Write-VdfFile $Environment.AcfPath $n;Set-FileReadOnly $Environment.AcfPath $true
 $state=Join-Path (Get-StateDir) 'lock.json';[pscustomobject]@{VersionId=$Version.id;Manifest=$Version.manifest;BuildId=$Version.buildid;Backup=$backup;CreatedUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 $state
}
function Clear-VersionLock { param([string]$AcfPath)
 $state=Join-Path (Get-StateDir) 'lock.json';if(Test-Path $AcfPath){Set-FileReadOnly $AcfPath $false};if(Test-Path $state){$s=Get-Content -Raw $state|ConvertFrom-Json;if(Test-Path $s.Backup){Copy-Item $s.Backup $AcfPath -Force};Remove-Item $state -Force};if(Test-Path $AcfPath){Set-FileReadOnly $AcfPath $false}
}
