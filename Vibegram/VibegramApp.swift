import SwiftUI

@main
struct VibegramApp: App {
    @StateObject private var store = AppStore()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear { delegate.store = store }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { store.showSettings = true }.keyboardShortcut(",")
            }
        }
        #endif
    }
}

#if os(macOS)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isConnected else { return .terminateNow }
        store.close()
        Task {
            for _ in 0..<100 {
                if !store.isConnected { sender.reply(toApplicationShouldTerminate: true); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
            store.error = "会话尚未关闭，请等待网络请求结束后再次退出。"
            sender.reply(toApplicationShouldTerminate: false)
        }
        return .terminateLater
    }
}
#endif
