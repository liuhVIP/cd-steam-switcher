#Requires -Version 3.0
. (Join-Path $PSScriptRoot 'TestUtils.ps1')
. (Join-Path $PSScriptRoot '..\lib\SteamEnv.ps1')

Start-TestRun

$tmpRoot = Join-Path $env:TEMP ('cdsw_steamenv_test_' + [guid]::NewGuid().ToString('N'))
$steamDir = Join-Path $tmpRoot 'steam'
$steamAppsDir = Join-Path $steamDir 'steamapps'
New-Item -ItemType Directory -Path $steamAppsDir -Force | Out-Null
$configDir = Join-Path $steamDir 'config'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

try {
    # libraryfolders.vdf
    $libVdf = @(
        '"libraryfolders"'
        '{'
        '    "0"'
        '    {'
        '        "path"  "G:\\SteamLibrary"'
        '    }'
        '    "1"'
        '    {'
        '        "path"  "D:\\Games"'
        '    }'
        '    "contentstatsid"    "12345"'
        '}'
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $steamAppsDir 'libraryfolders.vdf'), $libVdf, (New-Object System.Text.UTF8Encoding($false)))

    $libs = Get-SteamLibraryFolders -SteamPath $steamDir
    Assert-Equal 2 $libs.Count '解析出两个库目录'
    Assert-Equal 'G:\SteamLibrary' ([string]$libs[0].Path) '第一个库路径正确'
    Assert-Equal 'D:\Games' ([string]$libs[1].Path) '第二个库路径正确'

    # appmanifest 定位
    $fakeAcf = @(
        '"AppState"'
        '{'
        '    "appid"     "3321460"'
        '    "installdir"    "Crimson Desert"'
        '    "buildid"   "25116796"'
        '}'
    ) -join [Environment]::NewLine
    $gameLibDir = Join-Path $tmpRoot 'G_Library'
    New-Item -ItemType Directory -Path (Join-Path $gameLibDir 'steamapps') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $gameLibDir 'steamapps\appmanifest_3321460.acf'), $fakeAcf, (New-Object System.Text.UTF8Encoding($false)))

    $found = Find-AppManifestAcf -AppId '3321460' -LibraryPaths @($gameLibDir, 'D:\Games')
    Assert-True ($null -ne $found) '能在库目录找到 ACF'
    Assert-Equal $gameLibDir ([string]$found.LibraryDir) 'ACF 所在库正确'
    Assert-True (Test-Path -LiteralPath $found.AcfPath -PathType Leaf) 'ACF 路径存在'

    # loginusers.vdf
    $usersVdf = @(
        '"users"'
        '{'
        '    "76561198863912748"'
        '    {'
        '        "AccountName"    "liuho"'
        '        "PersonaName"    "Liu"'
        '        "mostrecent"     "1"'
        '        "RememberPassword"    "1"'
        '    }'
        '    "76561198000000000"'
        '    {'
        '        "AccountName"    "other"'
        '        "PersonaName"    "Other"'
        '        "mostrecent"     "0"'
        '    }'
        '}'
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $configDir 'loginusers.vdf'), $usersVdf, (New-Object System.Text.UTF8Encoding($false)))

    $users = Get-SteamLoginUsers -SteamPath $steamDir
    Assert-Equal 2 $users.Count '解析出两个 Steam 用户'
    Assert-Equal 'liuho' ([string]$users[0].AccountName) '第一个账号名正确'
    Assert-True ([bool]$users[0].MostRecent) 'mostrecent 解析为 true'

    $idText = (ConvertTo-SteamId64 -AccountId ([uint64]903647020)).ToString()
    Assert-Equal '76561198863912748' $idText 'AccountId 转 SteamId64 正确'

    # 注册表不存在时 Get-SteamActiveUser 应回退到 mostrecent（当前测试进程读真实注册表不可控，只验证结构）
    $active = Get-SteamActiveUser -SteamPath $steamDir
    Assert-True ($null -ne $active) '能返回活动/最近账号'
    Assert-True (-not [string]::IsNullOrWhiteSpace($active.AccountName)) '账号名非空'
} finally {
    if (Test-Path -LiteralPath $tmpRoot) { [System.IO.Directory]::Delete($tmpRoot, $true) }
}

Complete-TestRun