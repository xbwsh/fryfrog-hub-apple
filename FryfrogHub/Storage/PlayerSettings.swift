import Foundation
import Observation

/// 视频解码方式（mpv 内核）
enum DecodeMode: String, CaseIterable, Identifiable {
    case software
    case hardware
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .software: return "软解"
        case .hardware: return "硬解"
        case .auto: return "自动"
        }
    }

    var detail: String {
        switch self {
        case .software: return "纯 CPU 解码，兼容性最好"
        case .hardware: return "强制 VideoToolbox 硬解，失败时可能无声/黑屏"
        case .auto: return "优先硬解，失败自动回退软解"
        }
    }

    /// mpv hwdec 选项值（SW 渲染下必须用 -copy 变体，硬解帧拷回内存）
    var hwdecValue: String {
        switch self {
        case .software: return "no"
        case .hardware: return "videotoolbox-copy"
        case .auto: return "auto-copy"
        }
    }
}

/// 字幕选择偏好（跨视频按 title/lang 匹配恢复）
struct SubtitlePreference: Codable, Equatable {
    enum Kind: String, Codable {
        case off
        case builtin
        case external
    }

    var kind: Kind
    var title: String?
    var lang: String?
    var filename: String?
}

/// mpv 播放器设置（持久化到 UserDefaults）
@Observable
final class PlayerSettings {
    static let shared = PlayerSettings()

    private enum Keys {
        static let subtitlePreference = "subtitlePreference"
        static let decodeMode = "decodeMode"
    }

    private let defaults = UserDefaults.standard

    /// 视频解码方式（mpv 内核；hwdec 为每文件选项，设置后下次播放生效）
    var decodeMode: DecodeMode {
        didSet {
            defaults.set(decodeMode.rawValue, forKey: Keys.decodeMode)
            PreferenceSync.shared.scheduleUpload()
        }
    }

    /// 用户最近一次的字幕选择（nil = 无记忆，走默认）
    var subtitlePreference: SubtitlePreference? {
        didSet {
            if let subtitlePreference {
                do {
                    let data = try JSONEncoder().encode(subtitlePreference)
                    defaults.set(data, forKey: Keys.subtitlePreference)
                } catch {
                    AppLog.storage.warning("字幕偏好持久化编码失败: \(AppLog.describe(error))")
                    defaults.removeObject(forKey: Keys.subtitlePreference)
                }
            } else {
                defaults.removeObject(forKey: Keys.subtitlePreference)
            }
            PreferenceSync.shared.scheduleUpload()
        }
    }

    private init() {
        decodeMode = DecodeMode(rawValue: defaults.string(forKey: Keys.decodeMode) ?? "") ?? .auto
        if let data = defaults.data(forKey: Keys.subtitlePreference) {
            do {
                subtitlePreference = try JSONDecoder().decode(SubtitlePreference.self, from: data)
            } catch {
                AppLog.storage.warning("字幕偏好本地解码失败，重置为默认: \(AppLog.describe(error))")
                subtitlePreference = nil
            }
        }
    }
}
