# Steam 环境识别：安装路径、库目录、游戏 ACF、当前登录账号
#Requires -Version 3.0
. (Join-Path $PSScriptRoot 'Vdf.ps1')

$script:SteamRegistryRoot = 'HKCU:\Software\Valve\Steam'
$script:AppId = '3321460'
$script:MainDepotId = '3321461'
$script:SteamId64Base = [uint64]76561197960265728

function Get-SteamInstallPath {
    $value = $null
    try {
        $value = (Get-ItemProperty -Path $script:SteamRegistryRoot -Name SteamPath -ErrorAction Stop).SteamPath
    } catch {
        $value = $null
    }
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        if (Test-Path -LiteralPath (Join-Path $value 'steam.exe') -PathType Leaf) { return $value }
        return $value
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
        (Join-Path $env:ProgramFiles 'Steam'),
        (Join-Path $env:LOCALAPPDATA 'Steam')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'steam.exe') -PathType Leaf)) { return $c }
    }
    return $null
}

function Get-SteamLibraryFolders {
    param([Parameter(Mandatory = $true)][string]$SteamPath)
    $vdfPath = Join-Path $SteamPath 'steamapps\libraryfolders.vdf'
    if (-not (Test-Path -LiteralPath $vdfPath -PathType Leaf)) { return @() }

    $node = ConvertFrom-VdfText -Text ([System.IO.File]::ReadAllText($vdfPath))

    $dict = $node
    if (-not (Test-ContainsNumericKeys -Dictionary $node)) {
        foreach ($key in @($node.Keys)) {
            if ($node[$key] -is [System.Collections.IDictionary] -and (Test-ContainsNumericKeys -Dictionary $node[$key])) {
                $dict = $node[$key]
                break
            }
        }
    }

    $libs = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($dict.Keys)) {
        if ($key -match '^\d+$') {
            $entry = $dict[$key]
            if ($entry -is [System.Collections.IDictionary] -and $entry.Contains('path') -and -not [string]::IsNullOrWhiteSpace([string]$entry['path'])) {
                $libs.Add([pscustomobject]@{ Index = [int]$key; Path = [string]$entry['path'] })
            }
        }
    }
    return $libs.ToArray()
}

function Test-ContainsNumericKeys {
    param($Dictionary)
    if ($null -eq $Dictionary -or -not ($Dictionary -is [System.Collections.IDictionary])) { return $false }
    foreach ($key in @($Dictionary.Keys)) {
        if ($key -match '^\d+$') { return $true }
    }
    return $false
}

function Find-AppManifestAcf {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [string[]]$LibraryPaths
    )
    foreach ($lib in $LibraryPaths) {
        if ([string]::IsNullOrWhiteSpace($lib)) { continue }
        # Steam libraryfolders.vdf can retain entries for unplugged drives.
        # Join-Path throws when the drive itself does not exist, which used to
        # abort environment detection for the whole menu.  Ignore such stale
        # libraries and continue scanning the remaining entries.
        try {
            if (-not (Test-Path -LiteralPath $lib)) { continue }
            $candidate = Join-Path $lib ('steamapps\appmanifest_' + $AppId + '.acf')
        } catch {
            continue
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [pscustomobject]@{
                LibraryDir   = $lib
                SteamAppsDir = (Join-Path $lib 'steamapps')
                AcfPath      = $candidate
            }
        }
    }
    return $null
}

function Get-ManualGameDirPath {
    $stateDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'state'
    $path = Join-Path $stateDir 'game-path.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $saved = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        if ($saved.GameDir -and (Test-Path -LiteralPath ([string]$saved.GameDir) -PathType Container)) {
            return [string]$saved.GameDir
        }
    } catch { }
    return $null
}

function Set-ManualGameDirPath {
    param([Parameter(Mandatory = $true)][string]$GameDir,[switch]$SkipManifest)
    $GameDir = $GameDir.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) { throw ('游戏目录不存在: ' + $GameDir) }
    $acf = Join-Path (Join-Path (Split-Path -Parent $GameDir) '..') ('appmanifest_' + $script:AppId + '.acf')
    $acf = [IO.Path]::GetFullPath($acf)
    if (-not $SkipManifest -and -not (Test-Path -LiteralPath $acf -PathType Leaf)) { throw ('指定目录旁未找到 Steam ACF: ' + $acf) }
    $stateDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'state'
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    [pscustomobject]@{ GameDir = [IO.Path]::GetFullPath($GameDir) } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDir 'game-path.json') -Encoding UTF8
    return [IO.Path]::GetFullPath($GameDir)
}

function Clear-ManualGameDirPath {
    $path = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'state') 'game-path.json'
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

# ---- 账号识别 ----

function ConvertTo-SteamId64 {
    param([Parameter(Mandatory = $true)][uint64]$AccountId)
    return ($script:SteamId64Base + $AccountId)
}

function Get-SteamLoginUsers {
    param([Parameter(Mandatory = $true)][string]$SteamPath)
    $vdfPath = Join-Path $SteamPath 'config\loginusers.vdf'
    if (-not (Test-Path -LiteralPath $vdfPath -PathType Leaf)) { return @() }
    return (Get-SteamLoginUsersFromVdf -Path $vdfPath)
}

function Get-SteamLoginUsersFromVdf {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $node = ConvertFrom-VdfText -Text ([System.IO.File]::ReadAllText($Path))

    $dict = $node
    if (-not (Test-ContainsSteamIdKeys -Dictionary $node)) {
        foreach ($key in @($node.Keys)) {
            if ($node[$key] -is [System.Collections.IDictionary] -and (Test-ContainsSteamIdKeys -Dictionary $node[$key])) {
                $dict = $node[$key]
                break
            }
        }
    }

    $users = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($dict.Keys)) {
        if ($key -notmatch '^\d{17}$') { continue }
        $entry = $dict[$key]
        if (-not ($entry -is [System.Collections.IDictionary])) { continue }
        $users.Add([pscustomobject]@{
            SteamId64     = $key
            AccountName   = ([string]$entry['AccountName'])
            PersonaName   = ([string]$entry['PersonaName'])
            MostRecent    = ([string]$entry['mostrecent'] -eq '1')
            RememberPass  = ([string]$entry['RememberPassword'] -eq '1')
        })
    }
    return $users.ToArray()
}

function Test-ContainsSteamIdKeys {
    param($Dictionary)
    if ($null -eq $Dictionary -or -not ($Dictionary -is [System.Collections.IDictionary])) { return $false }
    foreach ($key in @($Dictionary.Keys)) {
        if ($key -match '^\d{17}$') { return $true }
    }
    return $false
}

function Get-SteamActiveAccountId {
    try {
        $item = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam\ActiveProcess' -Name ActiveUser -ErrorAction Stop
        return [uint64]$item.ActiveUser
    } catch {
        return $null
    }
}

function Get-SteamActiveUser {
    param([Parameter(Mandatory = $true)][string]$SteamPath)
    $activeId = Get-SteamActiveAccountId
    $users = Get-SteamLoginUsers -SteamPath $SteamPath
    if ($null -ne $activeId) {
        $want = (ConvertTo-SteamId64 -AccountId $activeId).ToString()
        $matched = @($users | Where-Object { $_.SteamId64 -eq $want })
        if ($matched.Count -gt 0) {
            $u = $matched[0]
            return [pscustomobject]@{ SteamId64 = $u.SteamId64; AccountName = $u.AccountName; PersonaName = $u.PersonaName; IsActive = $true }
        }
    }
    $recent = @($users | Where-Object { $_.MostRecent })
    if ($recent.Count -gt 0) {
        return [pscustomobject]@{ SteamId64 = $recent[0].SteamId64; AccountName = $recent[0].AccountName; PersonaName = $recent[0].PersonaName; IsActive = $false }
    }
    if ($users.Count -gt 0) {
        return [pscustomobject]@{ SteamId64 = $users[0].SteamId64; AccountName = $users[0].AccountName; PersonaName = $users[0].PersonaName; IsActive = $false }
    }
    return $null
}

# ---- 环境汇总 ----

function Get-CrimsonDesertEnvironment {
    $steamPath = Get-SteamInstallPath
    $libraries = @()
    if ($steamPath) { $libraries = Get-SteamLibraryFolders -SteamPath $steamPath }
    $libPaths = @($libraries | ForEach-Object { $_.Path })

    $acfInfo = Find-AppManifestAcf -AppId $script:AppId -LibraryPaths $libPaths
    if (-not $acfInfo) {
        $manualGameDir = Get-ManualGameDirPath
        if ($manualGameDir) {
            try {
                $manualAcf = [IO.Path]::GetFullPath((Join-Path (Join-Path (Split-Path -Parent $manualGameDir) '..') ('appmanifest_' + $script:AppId + '.acf')))
                if (Test-Path -LiteralPath $manualAcf -PathType Leaf) {
                    $steamApps = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $manualGameDir) '..'))
                    $acfInfo = [pscustomobject]@{ LibraryDir = (Split-Path -Parent $steamApps); SteamAppsDir = $steamApps; AcfPath = $manualAcf }
                }
            } catch { }
        }
    }
    $node = $null
    $acfPath = $null
    if ($acfInfo) {
        $acfPath = $acfInfo.AcfPath
        $node = Read-VdfFile -Path $acfPath
    }

    $state = $null
    $buildId = ''
    $depotManifest = ''
    $name = ''
    $language = ''
    $installdir = ''
    $lastUpdatedText = ''
    $stateFlags = ''
    $gameDir = $null
    $gameExe = $null
    $gameExeExists = $false
    $exeFileVersion = ''
    $acfReadOnly = $false

    if ($node) {
        $state = Get-AcfAppState -Node $node
        $buildId = [string](Get-AcfField -Node $node -Name 'buildid')
        $depotManifest = [string](Get-AcfDepotManifest -Node $node -DepotId $script:MainDepotId)
        $name = [string](Get-AcfField -Node $node -Name 'name')
        $language = [string](Get-VdfPathValue -Node $state -Path @('UserConfig', 'language'))
        $installdir = [string](Get-AcfField -Node $node -Name 'installdir')
        $lastUpdatedText = Get-UnixTimeLocal -UnixSeconds ([long](Get-AcfField -Node $node -Name 'LastUpdated'))
        $stateFlags = [string](Get-AcfField -Node $node -Name 'StateFlags')
        $acfReadOnly = Test-FileReadOnly -Path $acfPath

        if ($acfInfo -and -not [string]::IsNullOrWhiteSpace($installdir)) {
            $gameDir = Join-Path $acfInfo.SteamAppsDir ('common\' + $installdir)
            $gameExe = Join-Path $gameDir 'bin64\CrimsonDesert.exe'
            $gameExeExists = Test-Path -LiteralPath $gameExe -PathType Leaf
            if ($gameExeExists) {
                try { $exeFileVersion = [string](Get-Item -LiteralPath $gameExe).VersionInfo.FileVersion } catch { $exeFileVersion = '' }
            }
        }
    }

    $activeUser = $null
    if ($steamPath) { $activeUser = Get-SteamActiveUser -SteamPath $steamPath }

    return [pscustomobject]@{
        SteamPath      = $steamPath
        Libraries      = $libraries
        LibraryPaths   = $libPaths
        AcfFound       = ($null -ne $node)
        AcfPath        = $acfPath
        AcfReadOnly    = $acfReadOnly
        Name           = $name
        AppId          = $script:AppId
        DepotId        = $script:MainDepotId
        BuildId        = $buildId
        DepotManifest  = $depotManifest
        Language       = $language
        InstallDir     = $installdir
        StateFlags     = $stateFlags
        LastUpdated    = $lastUpdatedText
        GameDir        = $gameDir
        GameExe        = $gameExe
        GameExeExists  = $gameExeExists
        ExeFileVersion = $exeFileVersion
        ActiveUser     = $activeUser
    }
}
