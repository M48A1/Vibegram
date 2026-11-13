# Vibegram

**当前开发方向已调整：优先在官方 Telegram macOS 客户端上增加 UID/DC 显示，并沿用官方布局设置；随后再做 iOS。**

新的官方源码工程位于 `macOS/Telegram-Mac.xcworkspace`，改动说明和验证状态见 [macOS/VIBEGRAM.md](macOS/VIBEGRAM.md)。下文的 `Vibegram.xcodeproj`、TDLib 和演示空间属于之前的自建客户端原型，暂时保留供参考，不再作为新功能的实现基础。

面向个人日常使用的轻量 Telegram 原生客户端。Swift + SwiftUI，共享 iOS / iPadOS / macOS 核心逻辑。最低 iOS / iPadOS 17、macOS 14。

## 现在可以运行什么

- 可运行演示空间，消息只在内存中保留。iOS 演示无需第三方库；新机器编译 Mac 目标前先运行下方 TDLib 构建脚本。
- 聊天列表、标题搜索、聊天内搜索已加载消息及发言者、日期分隔、未读数、单列 / 分栏导航、文字气泡、复制文字、中文输入、设置、深色模式。
- 按对话保留草稿；真实账号草稿以 AES-GCM 加密保存到本机，关闭应用后可恢复，退出账号时清空。演示草稿只存内存。
- 群聊发言者姓名、失败文字消息的手动重试、常见登录错误的中文提示。重试仅处理 TDLib 允许原样重发且无需支付 Stars 的文字消息。
- 已实现 TDLib JSON 接口封装、授权状态处理、聊天排序、历史消息分页、消息更新 / 删除、文字发送和发送状态。
- 已实现本地数据库密钥的 Keychain 存储；API Hash 仅在登录初始化期间保留在内存中。

**当前已下载官方 TDLib 源码，并为本机 Apple Silicon Mac 构建和嵌入 TDLib。真实账号登录仍需自己的 API 凭证，尚未实测；iPhone/iPad 的 TDLib 二进制仍待构建。**

## 在 Xcode 中启动

1. 打开 `Vibegram.xcodeproj`。
2. Mac 选择 `Vibegram-macOS` scheme、`My Mac`，运行。
3. iPhone / iPad 选择 `Vibegram-iOS` scheme 和对应模拟器，运行。
4. 点击「先逛逛演示空间」，即可体验；设置里可以退出演示。
5. 真机运行前，在 Signing & Capabilities 中选择自己的开发团队，修改为自己的 Bundle ID。当前 `app.vibegram.personal` 只是占位标识。

Mac 发送快捷键为 Command + Return。演示消息不会发往 Telegram，也不会保存在磁盘上。

## 接入真实 Telegram

### 1. 准备 TDLib

官方源码位于 `Vendor/td`，固定版本为 `scripts/tdlib-revision.txt` 中的 commit（TDLib 1.8.70）。本机 Mac 构建产物是 `Vendor/TDLib/macOS/TDLib.framework`，已配置到 Mac 目标的 Embed TDLib 构建阶段。OpenSSL 3.5.9 从官方源码以 macOS 14 为部署目标构建，再静态链接进库，无需在运行机器上安装 Homebrew。OpenSSL 下载包的 SHA-256 校验值已固定在脚本中。

在这台机器上重建：

```sh
# 本机已安装这些依赖；其他开发机器首次构建时需要安装。
brew install cmake gperf
bash scripts/build-tdlib-macos.sh
bash scripts/check-tdlib.sh
```

构建脚本在源码缺失时从官方仓库下载固定 commit；源码存在但 commit 不匹配时会停止，不会覆盖已有修改。首次运行会从官方来源下载 OpenSSL 源码并校验；Homebrew 的 OpenSSL 预编译包可能要求较新系统，因此不直接用于分发库。默认并行度 4，可设置 `TDLIB_JOBS=2` 降低资源消耗。框架包含 TDLib 与 OpenSSL 许可证。

Swift 端使用当前 JSON 接口 `td_create_client_id`、`td_send`、`td_receive`。无需输入账号即可运行 smoke check，验证真实库加载、版本查询、授权状态和关闭事件；该检查已在生成的框架和 App 内嵌框架上通过，不代表账号登录或消息收发已经验证。接入层在创建客户端前关闭 TDLib 详细请求日志，避免登录信息进入控制台。

iOS / iPadOS 或 Intel Mac 仍需按照 [官方构建说明](https://github.com/tdlib/td#building) 和 [Apple 平台示例](https://github.com/tdlib/td/tree/master/example/ios) 生成对应切片。Mac 构建脚本默认构建本机架构，当前产物只有 arm64。

- **可选的 macOS 自定义库调试**（正常运行无需设置）：在 Xcode scheme 的 Run → Arguments → Environment Variables 中设置 `VIBEGRAM_TDLIB_PATH` 为构建好的 `libtdjson.dylib` 绝对路径。所有依赖必须可被动态加载器找到；沙盒可能阻止任意外部路径，可靠的方式仍是将库打包进 App。
- **其他 Apple 平台打包**（Mac 目标已配置）：将平台匹配的 `TDLib.framework` 添加到目标的 Frameworks, Libraries, and Embedded Content，选择 Embed & Sign；其主可执行文件名应为 `TDLib`。加载器查找 App 的 Frameworks/TDLib.framework/TDLib。Mac 还支持 Frameworks/libtdjson.dylib 和 Frameworks/tdjson.framework/tdjson。
- **iOS / iPadOS**：使用对应真机或模拟器切片的 framework / XCFramework，保证实际嵌入产物名是 `TDLib.framework`。当前加载器只支持导出 JSON 符号的动态构建；静态 XCFramework 需要另加 C 模块桥接，不能直接拖入后就使用。
- 检查 install names、rpath、架构和依赖是否完整。发布包不能依赖 Homebrew 路径、开发机器路径或下载运行时代码。

Mac 框架的打包、开发签名和 Xcode 嵌入已自动化；iPhone/iPad 尚未接入框架，没有二进制库时会明确提示，不会偷偷进入演示模式。

参考：[TDLib 入门](https://core.telegram.org/tdlib/getting-started)、[JSON C 接口](https://github.com/tdlib/td/blob/master/td/telegram/td_json_client.h)、[API schema](https://github.com/tdlib/td/blob/master/td/generate/scheme/td_api.tl)。

### 2. 使用自己的应用凭证

在 [my.telegram.org/apps](https://my.telegram.org/apps) 申请自己的 API ID / Hash，然后在 App 登录页填写。不要将凭证提交到仓库或发送到聊天中。当前每次重新启动后需要重新填写应用凭证，TDLib 会自行恢复仍有效的账号会话。

支持已有账号的手机号、验证码、两步验证密码、邮箱和邮箱验证码授权步骤。二维码、新账号注册、Premium 购买等授权流程尚未实现，遇到这些状态时会显示说明。

## 验证

```sh
sh scripts/check-models.sh
bash scripts/check-core.sh
bash scripts/check-tdlib.sh
xcodebuild -project Vibegram.xcodeproj -scheme Vibegram-macOS -configuration Debug -derivedDataPath .build/mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Vibegram.xcodeproj -scheme Vibegram-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
```

消息模型检查覆盖 64 位标识、中文与 Emoji、发送状态、时间戳、无效消息、媒体占位与安全错误提示。核心检查使用模拟传输，验证草稿加密与篡改检测、关闭后恢复、退出账号清理、群聊姓名、历史去重、窗口未激活时不标记已读、手动重试与演示数据隔离。编译和模拟测试不能替代真实账号集成测试。

## 当前限制和下一步

1. 已固定 TDLib 版本并完成本机 Mac 构建与嵌入；接下来补齐 iPhone/iPad 构建，再实测登录、重连、退出和文本收发。
2. 已加入群聊姓名、文字消息手动重试与加密本地草稿。接下来补发送权限判断、历史消息中的已读定位和完整的可见消息检测；当前仅在窗口激活、对话选中时根据消息行出现事件提交已读。草稿目前仅在本机保存，不同步到其他客户端。
3. 增加图片 / 文件 / 语音、回复、编辑、删除、代理设置及服务消息显示。目前媒体只显示文字占位；只加载主聊天列表的首批 200 个对话，没有归档、话题和完整列表分页。
4. 尽早完成 APNs 配置和设备注册；目前没有推送或通知扩展，后台运行不能保证收消息。
5. 补充真实设备和弱网验证、应用图标、辅助功能检查、隐私说明，然后进入 TestFlight。

秘密聊天、通话、Stories、多账号尚不支持。Mac 退出时请求 TDLib 关闭并等待数据库落盘；iOS 后台生命周期与被系统终止后的恢复仍需要真机验证。

本工程没有自建服务器、埋点或 AI 消息处理。公开发布前需要核对当时的 [Telegram API 条款](https://core.telegram.org/api/terms) 和 Apple 审核要求，并使公开版功能与条款匹配。

## 目录

```text
Vibegram/Core/       数据模型、状态管理、TDLib 桥接、Keychain
Vibegram/Views/      登录、聊天、设置
Vibegram.xcodeproj/  Mac 和 iPhone/iPad 两个目标、共享 schemes
Tests/              消息模型、应用状态与 TDLib 接入检查
scripts/            验证脚本
```

## 无凭证体验本轮功能

进入演示空间，在收藏夹输入文字后切换到其他对话，再切回来即可检查草稿保留。打开「林间小组」可以查看不同发言者和一条模拟失败消息；点击重试会在本地更新状态。聊天工具栏的放大镜（Mac 快捷键 Command + F）可以搜索已加载消息的正文或发言者。右键或长按消息可复制文字。演示空间里的操作不会访问 Telegram。
