# 红沙版本切换器 - 公共工具函数（中文输出/控制台编码）
#Requires -Version 3.0

function Set-ConsoleEncoding {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { $global:OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Write-StepInfo {
    param([string]$Message)
    Write-Host ('[信息] ' + $Message) -ForegroundColor Cyan
}

function Write-StepOk {
    param([string]$Message)
    Write-Host ('[完成] ' + $Message) -ForegroundColor Green
}

function Write-StepWarn {
    param([string]$Message)
    Write-Host ('[警告] ' + $Message) -ForegroundColor Yellow
}

function Write-StepErr {
    param([string]$Message)
    Write-Host ('[错误] ' + $Message) -ForegroundColor Red
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