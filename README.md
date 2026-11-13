# Vibegram

基于 Telegram 官方开源客户端，在 **macOS 和 iOS 同时增加 UID 与 DC 显示**。沿用官方布局、聊天和设置，不再基于旧 SwiftUI/TDLib 原型开发。

## 两端行为

- 用户资料页（含机器人和自己的个人资料页）直接显示完整的 64 位 **UID**，无需开启调试设置。
- 显示 **DC (avatar)**：从公开头像资源读取数据中心编号；没有头像、未返回资源或编号无效时显示 **Unavailable**。
- macOS 沿用资料行的复制菜单；iOS 点击或长按字段打开官方复制菜单。无效 DC 不提供复制操作。
- 沿用官方资料行样式、深色模式和语言资源回退机制。新增标签的英文回退值为 `DC (avatar)`、`Unavailable`。

**头像 DC 表示头像资源所在的数据中心，不能用来确认账号注册机房或实际地理位置。** 不根据 UID、手机号或当前账号的连接机房猜测对方 DC。没有新增网络请求。

范围是用户资料：群组、频道继续沿用官方资料页面；iOS 的设置首页不加字段，可进入自己的个人资料页查看。

## 恢复源码

本仓库原有 `macOS`、`iOS` 是 Git 引用，但缺少 `.gitmodules`，新检出的目录可能为空。使用下面的脚本恢复，而不是直接运行根目录的递归子模块更新：

```sh
python3 scripts/setup-official-clients.py --dependencies
```

两个平台都固定到 [scripts/official-clients.json](scripts/official-clients.json) 中的官方提交，并应用 [patches/official](patches/official) 的独立补丁。脚本可重复运行；遇到不同版本或补丁冲突会停止，不覆盖已有工作。只查看源码可省略 `--dependencies`；单独恢复一端可加 `--platform macOS` 或 `--platform iOS`。

macOS 官方仓库已迁移到 `TelegramMessenger/telegram-macos`。原引用 `48285355…` 无法从该仓库取得，现固定为 `246e3e95…`；iOS 保留原固定提交 `24638bc6…`。macOS 自带的共享 iOS 核心也固定在这个 iOS 提交。

工作目录内的修改保留为未提交状态；根目录补丁是恢复改动的依据。提交新版本时需要同时保存这些补丁和平台引用，或先在各自 fork 提交平台修改再更新引用。

## 检查与构建

```sh
bash scripts/check-official-clients.sh
```

该检查验证补丁已应用、Swift 语法、字符串资源格式与 iOS 字符串代码生成。**不等同于完整类型检查、应用构建或登录后的界面验收。**

macOS 的官方入口是 [macOS/Telegram-Mac.xcworkspace](macOS/Telegram-Mac.xcworkspace)，scheme 为 `Telegram`。依赖构建见 [官方构建指南](macOS/INSTALL.md)；Xcode 27 的可逆本机构建适配见 [XCODE27.md](macOS/XCODE27.md)。

本机可直接运行：

```sh
bash scripts/build-official-macos.sh
```

脚本使用源码固定的 Rust 1.96.1（需预先通过 rustup 安装，并准备 arm64 / x86_64 macOS 标准库），应用官方 Xcode 27 适配，构建原生依赖及本机架构的未签名 Debug 主程序。另有一个独立的 `macos-xcode27-support.patch`，只让官方适配脚本覆盖新增的 MTProtoEngine 工程；恢复源码脚本会一起应用它。构建目标调整可通过 `bash macOS/scripts/xcode27.sh revert` 撤回。

在本机 macOS 27 上还需关闭 Rust 符号剥离，避免固定工具链触发 [Rust 上游已记录的 LINKEDIT 对齐问题](https://github.com/rust-lang/rust/issues/157750)。这些本机参数已包含在构建脚本中，与 UID/DC 功能补丁分开保存。

iOS 通过官方 Bazel/Make.py 工具构建和生成 Xcode 工程，见 [iOS/README.md](iOS/README.md)。真机运行需要自己的 API 凭证、Bundle ID 和签名配置；不要把凭证写进补丁或提交到仓库。

本轮验证结果见下方；完整构建日志保存在本地 `.build/official-checks/`，不提交。

## 验证状态

- 已通过：两端 Swift 语法、字符串资源格式、iOS 字符串代码生成、补丁重复应用检查。
- iOS：Xcode 27.2、arm64 模拟器 Debug 全量构建通过（8,186 个构建动作），使用占位 API 配置并关闭模拟器 provisioning profile 检查，仅用于编译验证。
- macOS：Xcode 27.2、arm64 Debug 主程序及全部原生依赖构建通过。App 位于 `.build/official-macos/Build/Products/Debug/Telegram.app`，构建时关闭签名。
- 已登录账号的界面、复制、深色模式、长 UID、无头像用户和头像更新：尚未验收。
- 当前 macOS 产物为未签名 Debug；iOS 产物为模拟器版本，不能安装到 iPhone。iPhone 真机签名与本人 API 配置尚未完成。

界面验收时应看到 UID 与头像 DC 各占一行，沿用官方圆角与分隔线；复制菜单复制完整数字。无头像时 DC 显示不可用且无法复制，后续头像资源更新后应自动刷新。iOS 需按上游 AGENTS.md 录制资料页和复制操作并查看逐帧图后，再标记界面验收完成。

## 历史原型

`Vibegram.xcodeproj`、`Vibegram/`、`Vendor/` 与原来的 TDLib 脚本作为历史参考保留。它们不是当前功能的运行入口；旧功能记录见 [docs/prototype-client.md](docs/prototype-client.md)。
