# 简单 UI 辅助
function Format-Bytes { param([long]$Bytes);if($Bytes -ge 1GB){'{0:N1} GB'-f($Bytes/1GB)}elseif($Bytes -ge 1MB){'{0:N1} MB'-f($Bytes/1MB)}else{'{0:N0} KB'-f($Bytes/1KB)} }
function Show-ProgressBar { param([double]$Percent,[string]$Label='download');$p=[Math]::Max(0,[Math]::Min(100,$Percent));Write-Progress -Activity $Label -PercentComplete $p -Status ('{0:N1}%' -f $p) }
