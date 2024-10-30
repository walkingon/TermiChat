# TermiChat

运行在终端中的AI聊天助手

## 环境要求
1. 安装PowerShell 7+
2. 配置服务器地址和密钥。
    - 方式一：
        - 编辑config.json文件中"TermiChatHost"和"TermiChatKey"字段。
    - 方式二：
        - 在操作系统中设置环境变量
        - TermiChatHost  值如"oa.api2d.net"
        - TermiChatKey   值如"fkxxxxxxxxxxxxxxxxxxx"
3. 使用PowerShell运行TermiChat.ps1脚本（如使用config.json配置，需先在终端切换进入脚本所在目录下）。