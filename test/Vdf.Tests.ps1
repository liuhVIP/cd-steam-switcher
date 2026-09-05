#Requires -Version 3.0
. (Join-Path $PSScriptRoot 'TestUtils.ps1')
. (Join-Path $PSScriptRoot '..\lib\Acf.ps1')

Start-TestRun

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

$root = ConvertFrom-VdfText -Text $sample
Assert-True ($root.Contains('AppState')) 'root 包含 AppState'
$state = $root['AppState']
Assert-Equal '25116796' ([string](Get-VdfPathValue -Node $state -Path @('buildid'))) '读取 buildid'
Assert-Equal '3540302611239512787' ([string](Get-VdfPathValue -Node $state -Path @('InstalledDepots','3321461','manifest'))) '读取嵌套 manifest'

Set-VdfPathValue -Node $state -Path @('InstalledDepots','3321461','manifest') -Value '999000111'
Assert-Equal '999000111' ([string](Get-VdfPathValue -Node $state -Path @('InstalledDepots','3321461','manifest'))) '改写 manifest 生效'
Assert-Equal '25116796' ([string](Get-VdfPathValue -Node $state -Path @('buildid'))) '改写后 buildid 不变'

$text2 = ConvertTo-VdfText -Node $root
$root2 = ConvertFrom-VdfText -Text $text2
Assert-Equal '999000111' ([string](Get-VdfPathValue -Node $root2 -Path @('AppState','InstalledDepots','3321461','manifest'))) '序列化后 manifest 保留'
Assert-Equal '3321460' ([string](Get-VdfPathValue -Node $root2 -Path @('AppState','appid'))) '序列化后 appid 保留'

$pathSample = @(
    '"config"'
    '{'
    '    "path"  "G:\\SteamLibrary"'
    '}'
) -join [Environment]::NewLine

$pn = ConvertFrom-VdfText -Text $pathSample
Assert-Equal 'G:\SteamLibrary' ([string](Get-VdfPathValue -Node $pn -Path @('config','path'))) '解析双反斜杠为单反斜杠'
$pnText = ConvertTo-VdfText -Node $pn
$pn2 = ConvertFrom-VdfText -Text $pnText
Assert-Equal 'G:\SteamLibrary' ([string](Get-VdfPathValue -Node $pn2 -Path @('config','path'))) '路径转义往返一致'

Complete-TestRun