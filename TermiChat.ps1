
$TermiChatHost = $env:TermiChatHost
$TermiChatKey = $env:TermiChatKey

if ($null -eq $TermiChatHost || $null -eq $TermiChatKey) {
    if(Test-Path -Path ./config.json){
        Write-Host "读取配置文件"
        $config = Get-Content -Path ./config.json | ConvertFrom-Json
        $TermiChatHost = $config.TermiChatHost
        $TermiChatKey = $config.TermiChatKey
    }
}

if ($null -eq $TermiChatHost) {
    Write-Host "TermiChatHost 尚未设置"
    exit 1
}

if ($null -eq $TermiChatKey) {
    Write-Host "TermiChatKey 尚未设置"
    exit 1
}

Write-Host "Using TermiChatHost: $TermiChatHost"
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

# 请求非流式响应
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
            $result = Invoke-Expression $expression | Out-String
            AddMessage @{
                role         = "tool"
                tool_call_id = $toolCallId
                name         = $functionName
                content      = $result
            }
            RequestChat
        }
    }
    else {
        Write-Host "AI: " $assistantMessage.content
        WaitForUserInput
    }
}

# 暂未调通的流式响应
function RequestStreamChat {
    # 定义 SSE 服务器的 URL
    $sseUrl = "https://$TermiChatHost/v1/chat/completions"

    # 定义要发送的 JSON 数据
    $jsonData = @{
        "model"       = "gpt-4o-mini"
        "messages"    = $messages
        "tools"       = $tools
        "tool_choice" = "auto"
        "stream"      = $true
    } | ConvertTo-Json -Depth 6

    # 定义请求头
    $headers = @{
        "Authorization" = "Bearer $TermiChatKey"
        "Accept"        = "text/event-stream"
    }

    # 创建一个 HTTP 客户端
    $httpClient = New-Object System.Net.Http.HttpClient

    # 设置请求头
    foreach ($header in $headers.GetEnumerator()) {
        $httpClient.DefaultRequestHeaders.Add($header.Key, $header.Value)
    }

    # 发送 POST 请求并保持连接
    $response = $httpClient.PostAsync($sseUrl, [System.Net.Http.StringContent]::new($jsonData, [System.Text.Encoding]::UTF8, "application/json")).Result

    # 确保响应成功
    if ($response.IsSuccessStatusCode) {
        # 获取响应流
        $stream = $response.Content.ReadAsStreamAsync().Result

        # 创建一个 StreamReader 来读取流
        $reader = New-Object System.IO.StreamReader($stream)

        # 持续读取流中的数据
        while ($true) {
            # 读取一行数据
            $line = $reader.ReadLine()

            # 如果读取到的行不为空，则处理事件
            if ($line -and $line -ne "") {
                # 输出接收到的事件
                Write-Host $line
                if ($line -match "data: (.*)") {
                    $data = $matches[1]
                    if ($data -eq "data: [DONE]") {
                        break
                    }
                }
            }
        }
    }
    else {
        Write-Host "Error: $($response.StatusCode) - $($response.ReasonPhrase)"
    }
}


WaitForUserInput