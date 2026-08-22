import Foundation
import Observation

enum MusicCacheSizeOption: Int64, CaseIterable, Identifiable {
    case mb256 = 256
    case mb512 = 512
    case gb1 = 1024
    case gb2 = 2048
    case gb5 = 5120
    case gb10 = 10240
    case unlimited = 0

    var id: Int64 { rawValue }

    var title: String {
        switch self {
        case .mb256: return "256 MB"
        case .mb512: return "512 MB"
        case .gb1: return "1 GB"
        case .gb2: return "2 GB"
        case .gb5: return "5 GB"
        case .gb10: return "10 GB"
        case .unlimited: return "无限制"
        }
    }

    var bytes: Int64 {
        if self == .unlimited { return Int64.max }
        return rawValue * 1024 * 1024
    }

    static func from(bytes: Int64) -> MusicCacheSizeOption {
        if bytes == Int64.max { return .unlimited }
        let mb = bytes / (1024 * 1024)
        return MusicCacheSizeOption(rawValue: mb) ?? .gb2
    }
}

@Observable
final class MusicCacheSettings {
    static let shared = MusicCacheSettings()

    private enum Keys {
        static let maxBytes = "musicCache.maxBytes"
        static let autoCacheOnPlay = "musicCache.autoCacheOnPlay"
    }

    private let defaults = UserDefaults.standard

    var maxBytes: Int64 {
        didSet {
            defaults.set(maxBytes, forKey: Keys.maxBytes)
        }
    }

    var autoCacheOnPlay: Bool {
        didSet {
            defaults.set(autoCacheOnPlay, forKey: Keys.autoCacheOnPlay)
        }
    }

    var selectedOption: MusicCacheSizeOption {
        get { MusicCacheSizeOption.from(bytes: maxBytes) }
        set { maxBytes = newValue.bytes }
    }

    private init() {
        let initialMaxBytes: Int64
        if defaults.object(forKey: Keys.maxBytes) != nil {
            let stored = defaults.integer(forKey: Keys.maxBytes)
            var value: Int64
            if stored == Int.max {
                value = Int64.max
            } else if stored == 0 {
                value = MusicCacheSizeOption.gb2.bytes
            } else {
                value = Int64(stored)
                if value < 1024 * 1024 {
                    value = MusicCacheSizeOption.gb2.bytes
                }
            }
            if let obj = defaults.object(forKey: Keys.maxBytes) as? Int64 {
                value = obj
            }
            initialMaxBytes = value
        } else {
            initialMaxBytes = MusicCacheSizeOption.gb2.bytes
        }
        let finalMaxBytes: Int64 = defaults.object(forKey: Keys.maxBytes) == nil ? MusicCacheSizeOption.gb2.bytes : initialMaxBytes
        let initialAutoCache: Bool = defaults.object(forKey: Keys.autoCacheOnPlay) != nil ? defaults.bool(forKey: Keys.autoCacheOnPlay) : true
        self.maxBytes = finalMaxBytes
        self.autoCacheOnPlay = initialAutoCache
    }

    func formattedMax() -> String {
        if maxBytes == Int64.max { return "无限制" }
        return ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file)
    }
}
