# VDF/ACF 通用解析与序列化（保持插入顺序，兼容 Windows PowerShell 5.1）
#Requires -Version 3.0

function ConvertFrom-VdfText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $root = [ordered]@{}
    $stack = New-Object System.Collections.Stack
    $stack.Push($root) | Out-Null
    $pendingKey = $null
    $i = 0
    $len = $Text.Length

    while ($i -lt $len) {
        $ch = $Text[$i]

        if ($ch -eq '"') {
            $i++
            $sb = New-Object System.Text.StringBuilder
            while ($i -lt $len -and $Text[$i] -ne '"') {
                $c = $Text[$i]
                if ($c -eq '\' -and ($i + 1) -lt $len) {
                    $next = $Text[$i + 1]
                    if ($next -eq '"' -or $next -eq '\') {
                        [void]$sb.Append($next)
                        $i += 2
                        continue
                    }
                }
                [void]$sb.Append($c)
                $i++
            }
            if ($i -lt $len) { $i++ }

            $token = $sb.ToString()
            if ($null -eq $pendingKey) {
                $pendingKey = $token
            } elseif ($token -eq '{') {
                $child = [ordered]@{}
                $stack.Peek()[$pendingKey] = $child
                $stack.Push($child) | Out-Null
                $pendingKey = $null
            } else {
                $stack.Peek()[$pendingKey] = $token
                $pendingKey = $null
            }
            continue
        }

        if ($ch -eq '{') {
            if ($null -ne $pendingKey) {
                $child = [ordered]@{}
                $stack.Peek()[$pendingKey] = $child
                $stack.Push($child) | Out-Null
                $pendingKey = $null
            }
            $i++
            continue
        }

        if ($ch -eq '}') {
            if ($stack.Count -gt 1) { [void]$stack.Pop() }
            $pendingKey = $null
            $i++
            continue
        }

        if (-not [char]::IsWhiteSpace($ch)) {
            $start = $i
            while ($i -lt $len -and -not [char]::IsWhiteSpace($Text[$i]) -and
                   $Text[$i] -ne '{' -and $Text[$i] -ne '}') {
                $i++
            }
            $token = $Text.Substring($start, $i - $start)
            if ($null -eq $pendingKey) {
                $pendingKey = $token
            } elseif ($token -eq '{') {
                $child = [ordered]@{}
                $stack.Peek()[$pendingKey] = $child
                $stack.Push($child) | Out-Null
                $pendingKey = $null
            } else {
                $stack.Peek()[$pendingKey] = $token
                $pendingKey = $null
            }
            continue
        }

        $i++
    }

    return $root
}

function ConvertTo-VdfEscaped {
    # Steam 的 VDF 允许空字符串值；不要让参数绑定阶段拒绝用户 ACF 中的空字段。
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function ConvertTo-VdfText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Node,
        [int]$Indent = 0
    )

    $sb = New-Object System.Text.StringBuilder
    $pad = ("`t" * $Indent)

    foreach ($key in @($Node.Keys)) {
        $val = $Node[$key]
        if ($val -is [System.Collections.IDictionary]) {
            [void]$sb.Append($pad)
            [void]$sb.Append('"' + (ConvertTo-VdfEscaped -Value ([string]$key)) + '"')
            [void]$sb.AppendLine()
            [void]$sb.Append($pad + '{')
            [void]$sb.AppendLine()
            [void]$sb.Append((ConvertTo-VdfText -Node $val -Indent ($Indent + 1)))
            [void]$sb.Append($pad + '}')
            [void]$sb.AppendLine()
        } else {
            [void]$sb.Append($pad)
            [void]$sb.Append('"' + (ConvertTo-VdfEscaped -Value ([string]$key)) + '"' + "`t`t")
            [void]$sb.Append('"' + (ConvertTo-VdfEscaped -Value ([string]$val)) + '"')
            [void]$sb.AppendLine()
        }
    }

    return $sb.ToString()
}
