#Requires -Version 3.0
. (Join-Path $PSScriptRoot 'TestUtils.ps1')
. (Join-Path $PSScriptRoot '..\lib\Acf.ps1')

Start-TestRun

$tmpRoot = Join-Path $env:TEMP ('cdsw_acf_test_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$acfPath = Join-Path $tmpRoot 'appmanifest_3321460.acf'

try {
    $sample = @(
        '"AppState"'
        '{'
        '    "appid"     "3321460"'
        '    "name"      "Crimson Desert Enhanced"'
        '    "buildid"   "25116796"'
        '    "InstalledDepots"'
        '    {'
        '        "3321461"'
        '        {'
        '            "manifest"  "3540302611239512787"'
        '        }'
        '    }'
        '}'
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($acfPath, $sample, (New-Object System.Text.UTF8Encoding($false)))

    $node = Read-VdfFile -Path $acfPath
    Assert-Equal '25116796' ([string](Get-AcfBuildId -Node $node)) 'Read-VdfFile 读取 buildid'
    Assert-Equal '3540302611239512787' ([string](Get-AcfDepotManifest -Node $node)) '读取主 depot manifest'
    Assert-Equal '3321460' ([string](Get-AcfField -Node $node -Name 'appid')) '读取 appid'

    Set-AcfBuildId -Node $node -BuildId '25050808'
    Set-AcfDepotManifest -Node $node -Manifest '2880351385118582388'
    Write-VdfFile -Path $acfPath -Node $node

    $node2 = Read-VdfFile -Path $acfPath
    Assert-Equal '25050808' ([string](Get-AcfBuildId -Node $node2)) '写盘后 buildid 生效'
    Assert-Equal '2880351385118582388' ([string](Get-AcfDepotManifest -Node $node2)) '写盘后 manifest 生效'
    Assert-Equal '3321460' ([string](Get-AcfField -Node $node2 -Name 'appid')) '写盘后其他字段保留'

    $backupPath = Join-Path $tmpRoot 'backup.acf'
    Copy-FileBackup -Path $acfPath -BackupPath $backupPath
    Assert-True (Test-Path -LiteralPath $backupPath -PathType Leaf) '备份文件已生成'

    $throwBackup = $false
    try { Copy-FileBackup -Path $acfPath -BackupPath $backupPath } catch { $throwBackup = $true }
    Assert-True $throwBackup '备份已存在时默认抛错'
    Copy-FileBackup -Path $acfPath -BackupPath $backupPath -Force
    Assert-True $true '加 -Force 可覆盖备份'

    Assert-True (-not (Test-FileReadOnly -Path $acfPath)) '初始非只读'
    Set-FileReadOnly -Path $acfPath -ReadOnly $true
    Assert-True (Test-FileReadOnly -Path $acfPath) '只读已设置'
    Set-FileReadOnly -Path $acfPath -ReadOnly $false
    Assert-True (-not (Test-FileReadOnly -Path $acfPath)) '只读已清除'
} finally {
    if (Test-Path -LiteralPath $tmpRoot) { [System.IO.Directory]::Delete($tmpRoot, $true) }
}

Complete-TestRun