# 红沙版本切换器 - 公共工具函数（中文输出/控制台编码）
#Requires -Version 3.0

function Get-UiLanguage {
    try { $tz = [TimeZoneInfo]::Local.Id } catch { $tz = '' }
    if ($tz -in @('China Standard Time','Asia/Shanghai','Asia/Chongqing','Asia/Harbin','Asia/Urumqi')) { return 'zh-CN' }
    return 'en-US'
}
function Test-ChineseUi { return ((Get-UiLanguage) -eq 'zh-CN') }
function T { param([string]$Zh,[string]$En); if(Test-ChineseUi){$Zh}else{$En} }

function Set-ConsoleEncoding {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { $global:OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Write-StepInfo {
    param([string]$Message)
    Write-Host ('[' + (T '信息' 'INFO') + '] ' + $Message) -ForegroundColor Cyan
}

function Write-StepOk {
    param([string]$Message)
    Write-Host ('[' + (T '完成' 'OK') + '] ' + $Message) -ForegroundColor Green
}

function Write-StepWarn {
    param([string]$Message)
    Write-Host ('[' + (T '警告' 'WARN') + '] ' + $Message) -ForegroundColor Yellow
}

function Write-StepErr {
    param([string]$Message)
    Write-Host ('[' + (T '错误' 'ERROR') + '] ' + $Message) -ForegroundColor Red
}

function Get-UnixTimeLocal {
    param([long]$UnixSeconds)
    if ($UnixSeconds -le 0) { return '' }
    try {
        return [DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
    } catch {
        return ''
    }
}
