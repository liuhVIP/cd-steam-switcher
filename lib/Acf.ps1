# ACF（appmanifest_*.acf）读写封装：VDF 解析、字段改写、备份、只读锁
#Requires -Version 3.0
. (Join-Path $PSScriptRoot 'Vdf.ps1')

function Read-VdfFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "找不到文件: $Path"
    }
    $text = [System.IO.File]::ReadAllText($Path)
    return (ConvertFrom-VdfText -Text $text)
}

function Write-VdfFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Node
    )
    $text = ConvertTo-VdfText -Node $Node
    if (-not $text.EndsWith([Environment]::NewLine)) { $text += [Environment]::NewLine }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

function Get-VdfPathValue {
    param($Node, [Parameter(Mandatory = $true)][string[]]$Path)
    $cur = $Node
    foreach ($key in $Path) {
        if ($null -eq $cur -or -not ($cur -is [System.Collections.IDictionary]) -or -not $cur.Contains($key)) {
            return $null
        }
        $cur = $cur[$key]
    }
    return $cur
}

function Set-VdfPathValue {
    param($Node, [Parameter(Mandatory = $true)][string[]]$Path, $Value)
    if ($Path.Count -eq 0) { throw 'Path 不能为空' }
    $cur = $Node
    for ($j = 0; $j -lt ($Path.Count - 1); $j++) {
        $key = $Path[$j]
        if ($null -eq $cur -or -not ($cur -is [System.Collections.IDictionary])) {
            throw "中间节点不是字典: $key"
        }
        if (-not $cur.Contains($key) -or -not ($cur[$key] -is [System.Collections.IDictionary])) {
            $cur[$key] = [ordered]@{}
        }
        $cur = $cur[$key]
    }
    $lastKey = $Path[$Path.Count - 1]
    if (-not ($cur -is [System.Collections.IDictionary])) { throw '末尾节点不是字典' }
    $cur[$lastKey] = $Value
}

# ---- ACF 便捷访问 ----

function Get-AcfAppState {
    param($Node)
    if ($null -ne $Node -and $Node.Contains('AppState')) { return $Node['AppState'] }
    return $Node
}

function Get-AcfField {
    param($Node, [Parameter(Mandatory = $true)][string]$Name)
    $state = Get-AcfAppState -Node $Node
    if ($null -eq $state -or -not $state.Contains($Name)) { return $null }
    return $state[$Name]
}

function Get-AcfDepotManifest {
    param($Node, [string]$DepotId = '3321461')
    $state = Get-AcfAppState -Node $Node
    return (Get-VdfPathValue -Node $state -Path @('InstalledDepots', $DepotId, 'manifest'))
}

function Set-AcfDepotManifest {
    param($Node, [string]$DepotId = '3321461', [Parameter(Mandatory = $true)][string]$Manifest)
    $state = Get-AcfAppState -Node $Node
    Set-VdfPathValue -Node $state -Path @('InstalledDepots', $DepotId, 'manifest') -Value $Manifest
}

function Get-AcfBuildId {
    param($Node)
    return (Get-AcfField -Node $Node -Name 'buildid')
}

function Set-AcfBuildId {
    param($Node, [Parameter(Mandatory = $true)][string]$BuildId)
    $state = Get-AcfAppState -Node $Node
    Set-VdfPathValue -Node $state -Path @('buildid') -Value $BuildId
}

# ---- 备份与只读 ----

function Copy-FileBackup {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [switch]$Force
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "源文件不存在: $Path" }
    if ((Test-Path -LiteralPath $BackupPath -PathType Leaf) -and -not $Force) {
        throw "备份文件已存在: $BackupPath（如需覆盖请加 -Force）"
    }
    $dir = Split-Path -Parent $BackupPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -LiteralPath $Path -Destination $BackupPath -Force
}

function Set-FileReadOnly {
    param([Parameter(Mandatory = $true)][string]$Path, [bool]$ReadOnly = $true)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $attrs = $item.Attributes
    if ($ReadOnly) {
        if (-not ($attrs -band [System.IO.FileAttributes]::ReadOnly)) {
            $item.Attributes = $attrs -bor [System.IO.FileAttributes]::ReadOnly
        }
    } else {
        if ($attrs -band [System.IO.FileAttributes]::ReadOnly) {
            $item.Attributes = $attrs -bxor [System.IO.FileAttributes]::ReadOnly
        }
    }
}

function Test-FileReadOnly {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $attrs = (Get-Item -LiteralPath $Path -Force).Attributes
    return (($attrs -band [System.IO.FileAttributes]::ReadOnly) -eq [System.IO.FileAttributes]::ReadOnly)
}