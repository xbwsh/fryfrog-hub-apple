import SwiftUI
import Observation

struct RootView: View {
    @State private var auth = AuthService.shared
    @State private var isLoadingStatus = true

    var body: some View {
        Group {
            if isLoadingStatus {
                ProgressView("连接服务器…")
            } else if auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .overlay(alignment: .top) {
            // 全局提示（如 403 无操作权限）
            if let notice = GlobalNotice.shared.message {
                Text(notice)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.78), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                    .id(notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: GlobalNotice.shared.message)
        .task {
            await auth.restoreSession()
            await ServerConnection.shared.refreshActiveMode()
            isLoadingStatus = false
        }
    }
}

/// 全局轻提示（403 无操作权限等），顶部弹条自动消失
@Observable
final class GlobalNotice {
    static let shared = GlobalNotice()

    private(set) var message: String?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String) {
        message = text
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            if message == text {
                message = nil
            }
        }
    }
}

/// 诊断：窗口/根视图几何日志，写入 Documents/diag.txt。
/// 注意：只做纯文本记录，不做任何同步截屏（键盘动画期间同步截屏会导致页面内容消失）
enum Diag {
    static func log(_ context: String) {
        var lines = ["--- \(Date()) [\(context)] ---"]
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            lines.append("screen.bounds=\(windowScene.screen.bounds)")
            for window in windowScene.windows {
                // 确保窗口与根宿主视图背景与应用背景一致，内容未覆盖处不露纯黑
                window.backgroundColor = .appBackground
                if let root = window.rootViewController {
                    root.view.backgroundColor = .appBackground
                    lines.append("window.frame=\(window.frame)")
                    lines.append("root.frame=\(root.view.frame) root.bg=\(String(describing: root.view.backgroundColor))")
                    for sub in root.view.subviews {
                        lines.append("  sub=\(type(of: sub)) frame=\(sub.frame)")
                    }
                }
            }
        }
        let text = lines.joined(separator: "\n")
        print("[diag] \(text)")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diag.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data((text + "\n").utf8))
            try? handle.close()
        } else {
            try? (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
