# 轻量测试工具（无第三方依赖；PS5.1 / PS7 均可运行）
#Requires -Version 3.0

function Start-TestRun {
    $global:__CdSwitchTest = @{
        Passed   = 0
        Failed   = 0
        Failures = (New-Object System.Collections.Generic.List[string])
    }
}

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][bool]$Ok,
        [string]$Name = '',
        [string]$Detail = ''
    )
    $st = $global:__CdSwitchTest
    if ($Ok) { $st.Passed++ } else { $st.Failed++; [void]$st.Failures.Add($Name + $(if ($Detail) { ' | ' + $Detail } else { '' })) }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Name = 'Assert-Equal')
    $ok = $false
    if ($Expected -is [array] -or $Actual -is [array]) {
        $ok = (@(Compare-Object $Expected $Actual).Count -eq 0)
    } else {
        $ok = ($Expected -ceq $Actual)
    }
    Add-TestResult -Ok $ok -Name $Name -Detail ("期望=[$Expected] 实际=[$Actual]")
}

function Assert-NotEqual {
    param($Expected, $Actual, [string]$Name = 'Assert-NotEqual')
    $ok = ($Expected -cne $Actual)
    Add-TestResult -Ok $ok -Name $Name -Detail ("不应相等=[$Expected] 实际=[$Actual]")
}

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition, [string]$Name = 'Assert-True', [string]$Detail = '')
    Add-TestResult -Ok $Condition -Name $Name -Detail $Detail
}

function Assert-Match {
    param($Actual, [Parameter(Mandatory = $true)][string]$Pattern, [string]$Name = 'Assert-Match')
    $ok = ($Actual -match $Pattern)
    Add-TestResult -Ok $ok -Name $Name -Detail ("模式=[$Pattern] 实际=[$Actual]")
}

function Complete-TestRun {
    $st = $global:__CdSwitchTest
    Write-Host ('通过: ' + $st.Passed + '  失败: ' + $st.Failed) -ForegroundColor $(if ($st.Failed -eq 0) { 'Green' } else { 'Red' })
    if ($st.Failed -gt 0) {
        foreach ($f in $st.Failures) { Write-Host ('  失败项: ' + $f) -ForegroundColor Red }
        exit 1
    }
    exit 0
}