import Foundation
import SwiftUI
import Observation

/// 主题模式
enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// 主题设置（持久化到 UserDefaults，默认深色）
@Observable
final class ThemeSettings {
    static let shared = ThemeSettings()

    private enum Keys {
        static let mode = "theme.mode"
    }

    private let defaults = UserDefaults.standard

    /// 当前主题模式
    var mode: AppThemeMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.mode)
            PreferenceSync.shared.scheduleUpload()
        }
    }

    private init() {
        if let raw = defaults.string(forKey: Keys.mode),
           let mode = AppThemeMode(rawValue: raw) {
            self.mode = mode
        } else {
            self.mode = .dark
        }
    }
}
