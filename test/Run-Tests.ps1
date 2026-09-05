# 本地回归：逐个运行 test\*.Tests.ps1（子进程隔离，非 0 退出码即失败）
#Requires -Version 3.0
$script:RunRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$currentExe = (Get-Process -Id $PID).Path

$tests = @(Get-ChildItem -LiteralPath $script:RunRoot -Filter '*.Tests.ps1' | Sort-Object Name)
if ($tests.Count -eq 0) { Write-Host '未找到测试文件'; exit 1 }

$failedFiles = New-Object System.Collections.Generic.List[string]
$passedFiles = New-Object System.Collections.Generic.List[string]

foreach ($t in $tests) {
    Write-Host ('==> ' + $t.Name) -ForegroundColor Cyan
    & $currentExe -NoProfile -ExecutionPolicy Bypass -File $t.FullName
    if ($LASTEXITCODE -eq 0) {
        $passedFiles.Add($t.Name) | Out-Null
    } else {
        $failedFiles.Add($t.Name) | Out-Null
        Write-Host ('  [失败] ' + $t.Name) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host ('测试文件: 共 ' + $tests.Count + '，通过 ' + $passedFiles.Count + '，失败 ' + $failedFiles.Count) -ForegroundColor $(if ($failedFiles.Count -eq 0) { 'Green' } else { 'Red' })
if ($failedFiles.Count -gt 0) {
    exit 1
}
exit 0