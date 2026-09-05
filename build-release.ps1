#Requires -Version 3.0
[CmdletBinding()]
param(
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$versionFile = Join-Path $root 'versions.json'

if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    throw "Missing versions.json: $versionFile"
}

$versionData = Get-Content -Raw -LiteralPath $versionFile | ConvertFrom-Json
$version = [string]$versionData.tool_version
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid tool_version in versions.json: $version"
}

if (-not $SkipTests) {
    Write-Host '[1/4] Running tests...' -ForegroundColor Cyan
    $testRunner = Join-Path $root 'test\Run-Tests.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testRunner
    if ($LASTEXITCODE -ne 0) {
        throw "Tests failed with exit code $LASTEXITCODE. Release was not created."
    }
} else {
    Write-Host '[1/4] Tests skipped.' -ForegroundColor Yellow
}

$distRoot = Join-Path $root 'dist'
$releaseRoot = Join-Path $distRoot ('release-v' + $version)
$packageName = -join @([char]32418,[char]27801,[char]29256,[char]26412,[char]20999,[char]25442,[char]22120)
$packageRoot = Join-Path $releaseRoot $packageName
$zipFileName = '{0}-v{1}.zip' -f $packageName, $version
$zipPath = Join-Path $releaseRoot $zipFileName

# Only remove the exact versioned output directory below this project's dist.
$expectedParent = [IO.Path]::GetFullPath($distRoot).TrimEnd('\') + '\'
$resolvedRelease = [IO.Path]::GetFullPath($releaseRoot)
if (-not $resolvedRelease.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe release path: $resolvedRelease"
}
if (Test-Path -LiteralPath $releaseRoot) {
    Remove-Item -LiteralPath $releaseRoot -Recurse -Force
}

Write-Host ('[2/4] Creating release v' + $version + '...') -ForegroundColor Cyan
New-Item -ItemType Directory -Path (Join-Path $packageRoot 'lib') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $packageRoot 'state') -Force | Out-Null

$rootFiles = @(
    'menu.ps1',
    'versions.json',
    'README.md',
    'VERSION_DATA.md',
    'LICENSE'
)
foreach ($file in $rootFiles) {
    $source = Join-Path $root $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required release file is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination $packageRoot -Force
}
$launcher = Get-ChildItem -LiteralPath $root -Filter '*.bat' -File | Where-Object { $_.Name -ne '打包.bat' } | Select-Object -First 1
if (-not $launcher) {
    throw 'Required launcher BAT file is missing.'
}
Copy-Item -LiteralPath $launcher.FullName -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $root 'lib\*.ps1') -Destination (Join-Path $packageRoot 'lib') -Force
New-Item -ItemType File -Path (Join-Path $packageRoot 'state\.gitkeep') -Force | Out-Null

$packagedVersion = [string]((Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'versions.json') | ConvertFrom-Json).tool_version)
if ($packagedVersion -ne $version) {
    throw "Packaged version mismatch: expected $version, got $packagedVersion"
}

Write-Host '[3/4] Compressing ZIP...' -ForegroundColor Cyan
Compress-Archive -Path $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force

Write-Host '[4/4] Release complete.' -ForegroundColor Green
$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
Write-Host ('Version : ' + $version)
Write-Host ('ZIP     : ' + $zipPath)
Write-Host ('SHA-256 : ' + $hash.Hash)

[pscustomobject]@{
    Version = $version
    ZipPath = $zipPath
    Sha256 = $hash.Hash
}
