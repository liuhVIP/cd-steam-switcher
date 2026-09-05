#Requires -Version 3.0
. (Join-Path $PSScriptRoot 'TestUtils.ps1')
. (Join-Path $PSScriptRoot '..\lib\Registry.ps1')
Start-TestRun
$versions = @(Get-VersionList -Path (Join-Path $PSScriptRoot '..\versions.json'))
Assert-Equal 4 $versions.Count '登记表含四个 2.x 版本'
Assert-Equal '2.01.00' $versions[0].id '版本按降序'
Assert-True (Test-VersionScope '2.0.02') '2.x 在范围内'
Assert-True (-not (Test-VersionScope '1.12.00')) '1.x 排除'
Assert-Equal 1 (Compare-GameVersion '2.01.00' '2.00.01') '版本比较'
Assert-Equal 0 (Compare-GameVersion '2.0.02' '2.00.02') '补零比较'
$m=Find-VersionByManifest -Manifest '2880351385118582388' -Path (Join-Path $PSScriptRoot '..\versions.json')
Assert-Equal '2.00.02' $m.id '按 manifest 查找'
Complete-TestRun
