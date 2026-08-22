import SwiftUI

@main
struct FryfrogHubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var theme = ThemeSettings.shared
    private var privacy = PrivacySettings.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var hasEnteredForeground = false

    var body: some Scene {
        WindowGroup {
            RootView()
                // 背景铺满整个窗口（含安全区），避免边缘露出窗口纯黑底色
                .background(Color.appBackground, ignoresSafeAreaEdges: .all)
                .preferredColorScheme(theme.mode.colorScheme)
                .onAppear {
                    AppAppearance.applyWindowInterfaceStyle(AppAppearance.style(for: theme.mode))
                }
                .onChange(of: theme.mode) { _, newMode in
                    // preferredColorScheme 不总能驱动状态栏前景色，显式设置窗口外观保证
                    // 浅色=黑色状态栏、深色=浅色状态栏
                    AppAppearance.applyWindowInterfaceStyle(AppAppearance.style(for: newMode))
                }
                .overlay {
                    // 隐私模式下，离开前台（多任务/后台）时用遮罩盖住内容，防止预览泄露
                    // 启动初期 scenePhase 可能短暂不是 active，不能在连接服务器时
                    // 提前显示隐私遮罩，否则会与 RootView 的加载提示重叠。
                    if privacy.isEnabled && hasEnteredForeground && scenePhase != .active {
                        PrivacyShieldView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: scenePhase)
                .animation(.easeInOut(duration: 0.2), value: privacy.isEnabled)
                // 回到前台时重新探测局域网，方便移动设备回到家后自动切回局域网优先
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        hasEnteredForeground = true
                        Task { await ServerConnection.shared.refreshActiveMode() }
                    }
                }
                .onAppear {
                    if scenePhase == .active {
                        hasEnteredForeground = true
                    }
                }
        }
    }
}

/// 统一设置 UIWindow 背景色：即使 SwiftUI 内容未覆盖到窗口边缘，也不会露出纯黑
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        applyWindowBackground()
        return true
    }

    /// 窗口在启动后稍晚创建，轮询到窗口后再统一上色
    private func applyWindowBackground() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        if windows.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyWindowBackground()
            }
            return
        }
        for window in windows {
            window.backgroundColor = .appBackground
            // 根宿主视图默认是系统背景色（深色下为纯黑），SwiftUI 内容未铺满时两侧会露出黑条
            window.rootViewController?.view.backgroundColor = .appBackground
        }
    }
}

/// 全局窗口外观控制：preferredColorScheme 不一定驱动状态栏前景色，这里显式设置窗口外观
enum AppAppearance {
    static func style(for mode: AppThemeMode) -> UIUserInterfaceStyle {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return .unspecified
        }
    }

    static func applyWindowInterfaceStyle(_ style: UIUserInterfaceStyle) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}
