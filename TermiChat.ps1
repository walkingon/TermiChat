
$TermiChatHost = $env:TermiChatHost
$TermiChatKey = $env:TermiChatKey

if ($null -eq $TermiChatHost) {
    Write-Host "环境变量：TermiChatHost 尚未设置"
    exit 1
}

if ($null -eq $TermiChatKey) {
    Write-Host "环境变量：TermiChatKey 尚未设置"
    exit 1
}

Write-Host "TermiChatHost: $TermiChatHost"
#Write-Host "TermiChatKey: $TermiChatKey"

# 定义messages列表
$messages = New-Object System.Collections.ArrayList

function AddMessage {
    param([object]$msg)
    $messages.Add($msg) | Out-Null
    $content = $messages | ConvertTo-Json -Depth 6
    # 检查log目录并创建
    if (-not (Test-Path "./log")) {
        New-Item -ItemType Directory -Path "./log" | Out-Null
    }
    # 将$content添加进`./log/messages.json`文件中
    Set-Content -Path "./log/messages.json" -Value $content
}

AddMessage @{
    role    = "system"
    content = "你现在是一个有用的PowerShell终端助手，可以使用PowerShell命令帮助用户解决问题。"
}

$tools = @(
    @{
        "type"        = "function"
        "function"    = @{
            "name" = "invoke_expression"
        }
        "description" = "运行PowerShell命令表达式"
        "parameters"  = @{
            "type"       = "object"
            "properties" = @{
                "expression" = @{
                    "type"        = "string"
                    "description" = "需要执行的PowerShell命令表达式，例如：Get-ChildItem"
                }
            }
            "required"   = @("expression")
        }
    }
)

function WaitForUserInput {
    $userInput = Read-Host "你"
    if ($userInput -eq "exit") {
        Write-Host "退出交互模式"
        break
    }
    AddMessage @{
        role    = "user"
        content = $userInput
    }
    RequestChat
}

function RequestChat {
    $body = @{
        "model"       = "gpt-4o-mini"
        "messages"    = $messages
        "tools"       = $tools
        "tool_choice" = "auto"
    } | ConvertTo-Json -Depth 6

    $response = Invoke-RestMethod -Uri "https://$TermiChatHost/v1/chat/completions" -Method POST -Headers @{
        "Authorization" = "Bearer $TermiChatKey"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    } -Body $body

    $assistantMessage = $response.choices[0].message
    AddMessage $assistantMessage
    if ($response.choices[0].finish_reason -eq "tool_calls") {
        $toolCall = $response.choices[0].message.tool_calls[0]
        $toolCallId = $toolCall.id
        $functionName = $toolCall.function.name
        $functionArgs = $toolCall.function.arguments | ConvertFrom-Json
        if ($functionName -eq "invoke_expression") {
            $expression = $functionArgs.expression
            $result = Invoke-Expression $expression
            AddMessage @{
                role         = "tool"
                tool_call_id = $toolCallId
                name         = $functionName
                content      = $result.ToString()
            }
            RequestChat
        }
    }
    else {
        Write-Host "AI: " $assistantMessage.content
        WaitForUserInput
    }
}


WaitForUserInput