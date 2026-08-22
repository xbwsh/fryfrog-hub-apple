import Foundation
import Observation

/// 隐私模式设置（持久化到 UserDefaults）
@Observable
final class PrivacySettings {
    static let shared = PrivacySettings()

    private enum Keys {
        static let isEnabled = "privacy.isEnabled"
        static let autoDisableOnLAN = "privacy.autoDisableOnLAN"
    }

    private let defaults = UserDefaults.standard

    /// 隐私模式总开关：开启后隐藏/模糊成人内容
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            PreferenceSync.shared.scheduleUpload()
            if isEnabled {
                Task { @MainActor in AuthImageLoader.shared.purgeAll() }
            }
        }
    }

    /// 局域网自动关闭隐私模式
    var autoDisableOnLAN: Bool {
        didSet {
            defaults.set(autoDisableOnLAN, forKey: Keys.autoDisableOnLAN)
            if autoDisableOnLAN {
                Task { @MainActor in self.checkAutoDisableIfNeeded() }
            }
        }
    }

    private init() {
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        autoDisableOnLAN = defaults.bool(forKey: Keys.autoDisableOnLAN)
    }

    @MainActor
    func checkAutoDisableIfNeeded() {
        guard autoDisableOnLAN, isEnabled else { return }
        // 仅在已判定为局域网连接时自动关闭
        if ServerConnection.shared.effectiveMode == .lan {
            isEnabled = false
        }
    }
}
