import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: AppStore
    @State private var apiID = ""
    @State private var apiHash = ""
    @State private var credential = ""
    var fieldTitle: String {
        switch store.authState {
        case "authorizationStateWaitPhoneNumber": "手机号（含国家区号，如 +86）"
        case "authorizationStateWaitCode": "Telegram 登录验证码"
        case "authorizationStateWaitPassword": "两步验证密码"
        case "authorizationStateWaitEmailAddress": "登录邮箱"
        case "authorizationStateWaitEmailCode": "邮箱验证码"
        default: "等待 Telegram 响应…"
        }
    }
    var acceptsInput: Bool {
        ["authorizationStateWaitPhoneNumber", "authorizationStateWaitCode", "authorizationStateWaitPassword", "authorizationStateWaitEmailAddress", "authorizationStateWaitEmailCode"].contains(store.authState)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Spacer(minLength: 44)
                Image(systemName: "leaf.fill").font(.system(size: 38)).foregroundStyle(Palette.accent)
                    .frame(width: 80, height: 80).background(Palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 12) {
                    Text("少一点喧嚣，\n多一点对话。").font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("Vibegram · 你的轻量 Telegram 客户端")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    if !store.isConnected {
                        Text("连接你的 Telegram").font(.headline)
                        TextField("API ID", text: $apiID).textFieldStyle(.roundedBorder)
                        SecureField("API Hash", text: $apiHash).textFieldStyle(.roundedBorder)
                        Link("在 my.telegram.org 获取应用凭证 ↗", destination: URL(string: "https://my.telegram.org/apps")!).font(.caption)
                        Button {
                            store.connect(apiID: apiID, apiHash: apiHash)
                            if store.isConnected { apiHash = "" }
                        } label: { Text("连接 Telegram").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.borderedProminent)
                    } else if acceptsInput {
                        Text(fieldTitle).font(.headline)
                        if store.authState == "authorizationStateWaitPassword" {
                            SecureField(fieldTitle, text: $credential).textFieldStyle(.roundedBorder)
                        } else {
                            TextField(fieldTitle, text: $credential).textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                        }
                        if store.authState == "authorizationStateWaitCode" {
                            Text("验证码可能发送到已登录的 Telegram 设备，请查看官方客户端。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("继续") { store.authenticate(credential) }.buttonStyle(.borderedProminent)
                            .disabled(store.busy || credential.isEmpty)
                    } else {
                        if store.busy || store.authState.isEmpty { ProgressView("正在连接…") }
                        else { Text("当前登录步骤尚未支持，请先通过官方客户端完成注册或额外验证，再重新连接。")
                            .font(.subheadline).foregroundStyle(.secondary) }
                    }
                    if store.isConnected { Button("断开连接") { store.close() }.font(.caption) }
                }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 20))
                if !store.isConnected {
                    Button { store.startDemo() } label: {
                        HStack { Text("先逛逛演示空间"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                }
                Text("独立第三方客户端，使用 Telegram API。\n当前为开发预览版；暂不支持媒体收发和推送通知。")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(5)
                Spacer(minLength: 36)
            }.padding(28).frame(maxWidth: 470).frame(maxWidth: .infinity)
        }.background(Palette.canvas)
            .onChange(of: store.authState) { _, _ in credential = "" }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Vibegram 0.1 · 开发预览") {
                    LabeledContent("当前模式", value: store.isDemo ? "演示空间" : "Telegram")
                    LabeledContent("连接状态", value: store.connection)
                    Text("轻量、原生，给真正重要的对话留一点空间。")
                        .foregroundStyle(.secondary)
                }
                Section("数据与隐私") {
                    Text(store.isDemo ? "演示消息仅保留在内存中，退出演示后清除。" : "消息由 TDLib 保存在本机；数据库密钥保存在系统 Keychain。Telegram 会话不会上传到自建服务器。")
                    Text("暂不支持媒体收发、推送通知、秘密聊天与通话。消息搜索仅覆盖当前已加载的记录。真实账号草稿会加密保存在本机，退出账号时清除。")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Telegram API 说明", destination: URL(string: "https://core.telegram.org/api")!)
                }
                Section {
                    if store.isDemo {
                        Button("退出演示空间") { store.leaveDemo(); dismiss() }
                    } else {
                        Button("退出 Telegram 账号", role: .destructive) { confirmLogout = true }.disabled(store.busy)
                    }
                }
            }.formStyle(.grouped).navigationTitle("设置")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .confirmationDialog("退出后会清除 TDLib 本地会话和缓存。", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("退出账号", role: .destructive) { store.logout(); dismiss() }
                }
        }
        #if os(macOS)
        .frame(width: 480, height: 460)
        #endif
    }
}
