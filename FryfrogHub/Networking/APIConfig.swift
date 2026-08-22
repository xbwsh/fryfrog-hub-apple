import Foundation
import Observation

/// 当前正在使用的服务器连接方式
enum ServerConnectionMode: String {
    case lan
    case `public`

    var title: String {
        switch self {
        case .lan: return "局域网"
        case .public: return "公网"
        }
    }
}

/// 服务器连接配置（持久化到 UserDefaults，支持 IPv6 如 `http://[2409:...]:20058`）
/// 可同时配置公网（域名）与局域网地址，两者共用协议与端口；
/// 优先使用局域网，局域网连不通时自动切换到公网。
@Observable
final class ServerConnection {
    static let shared = ServerConnection()

    private enum Keys {
        static let scheme = "server.scheme"
        static let port = "server.port"
        static let publicHost = "server.publicHost"
        static let lanHost = "server.lanHost"
        static let activeMode = "server.activeMode"
    }

    /// 旧版单一地址存储键（迁移用）
    private static let legacyBaseURLKey = "serverBaseURL"

    private let defaults = UserDefaults.standard

    /// 协议，仅支持 http/https
    var scheme: String {
        didSet { defaults.set(scheme, forKey: Keys.scheme) }
    }

    /// 端口，默认 20058
    var port: String {
        didSet { defaults.set(port, forKey: Keys.port) }
    }

    /// 公网主机地址（域名或公网 IP，不含协议与端口）
    var publicHost: String {
        didSet { defaults.set(publicHost, forKey: Keys.publicHost) }
    }

    /// 局域网主机地址（不含协议与端口，选填）
    var lanHost: String {
        didSet { defaults.set(lanHost, forKey: Keys.lanHost) }
    }

    /// 当前生效的连接方式；登录/回到前台/失败切换时更新
    var activeMode: ServerConnectionMode {
        didSet { defaults.set(activeMode.rawValue, forKey: Keys.activeMode) }
    }

    /// 正在探测局域网（进度指示用）
    private(set) var isProbing = false

    private init() {
        scheme = defaults.string(forKey: Keys.scheme) ?? "http"
        port = defaults.string(forKey: Keys.port) ?? "20058"
        publicHost = defaults.string(forKey: Keys.publicHost) ?? ""
        lanHost = defaults.string(forKey: Keys.lanHost) ?? ""
        // 清理已移除的异地组网残留键
        if defaults.object(forKey: "server.meshHost") != nil {
            defaults.removeObject(forKey: "server.meshHost")
        }
        if let raw = defaults.string(forKey: Keys.activeMode), let mode = ServerConnectionMode(rawValue: raw) {
            activeMode = mode
        } else {
            activeMode = .public
        }
        // 兼容旧 mesh 残留：若曾持久化为 mesh 回退到 public
        if defaults.string(forKey: Keys.activeMode) == "mesh" {
            activeMode = .public
            defaults.set(activeMode.rawValue, forKey: Keys.activeMode)
        }
        migrateLegacyBaseURLIfNeeded()
    }

    /// 旧版本只保存了单一完整地址，迁移为 公网主机 + 协议 + 端口
    private func migrateLegacyBaseURLIfNeeded() {
        guard publicHost.isEmpty,
              let legacy = defaults.string(forKey: Self.legacyBaseURLKey),
              let url = URL(string: legacy),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else { return }
        scheme = components.scheme ?? "http"
        port = components.port.map(String.init) ?? "20058"
        publicHost = host
        defaults.removeObject(forKey: Self.legacyBaseURLKey)
    }
}

extension ServerConnection {
    /// 是否已配置局域网地址
    var hasLAN: Bool { !trimmedHost(lanHost).isEmpty }

    /// 是否已配置任意地址
    var hasAnyAddress: Bool { !trimmedHost(publicHost).isEmpty || hasLAN }

    /// 当前请求应使用的连接方式（未配置局域网时强制走公网）
    var effectiveMode: ServerConnectionMode {
        if activeMode == .lan && !hasLAN { return .public }
        return activeMode
    }

    /// 局域网完整地址（未配置时 nil）
    var lanURLString: String? { urlString(for: .lan) }

    /// 公网完整地址（未配置时 nil）
    var publicURLString: String? { urlString(for: .public) }

    /// 当前生效的完整地址（未配置时为空字符串）
    var activeURLString: String { urlString(for: effectiveMode) ?? "" }

    /// 当前生效的基础 URL
    var baseURL: URL? { URL(string: activeURLString) }

    /// 构造某连接方式的完整地址；主机未配置或端口非法时返回 nil
    func urlString(for mode: ServerConnectionMode) -> String? {
        let host = trimmedHost(mode == .lan ? lanHost : publicHost)
        guard !host.isEmpty else { return nil }
        // IPv6 地址需带方括号，用户直接粘贴裸 IPv6 时自动补齐
        let hostWithBrackets = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let portValue = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portNumber = Int(portValue), (1...65535).contains(portNumber) else { return nil }
        return "\(scheme)://\(hostWithBrackets):\(portNumber)"
    }

    /// 另一个（备选）连接方式
    func alternateMode(for mode: ServerConnectionMode) -> ServerConnectionMode {
        mode == .lan ? .public : .lan
    }

    /// 备选连接方式的完整地址（未配置时 nil）
    func alternateURLString(for mode: ServerConnectionMode) -> String? {
        urlString(for: alternateMode(for: mode))
    }

    /// 将后端返回的相对路径（如 `/api/v1/video/series/1/cover`）拼接为完整 URL
    func imageURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        guard !activeURLString.isEmpty else { return nil }
        let trimmed = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: activeURLString + trimmed)
    }

    /// 探测局域网是否可达（短超时），可达返回 true
    func probeLAN(timeout: TimeInterval = 3) async -> Bool {
        guard let lan = lanURLString, let url = URL(string: lan + "/api/v1/auth/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return false
        }
    }

    /// 重新评估连接方式：局域网优先，不通则退回公网
    func refreshActiveMode() async {
        await updateIsProbing(true)
        defer { Task { await updateIsProbing(false) } }

        guard hasLAN else {
            if effectiveMode != .public {
                await setActiveMode(.public)
            }
            return
        }
        let lanReachable = await probeLAN()
        let target: ServerConnectionMode = lanReachable ? .lan : .public
        if effectiveMode != target {
            await setActiveMode(target)
        }
    }

    /// 切换当前生效的连接方式（统一跳回主线程变更，保证视图观察安全）
    func setActiveMode(_ mode: ServerConnectionMode) async {
        await MainActor.run {
            activeMode = mode
            if mode == .lan { PrivacySettings.shared.checkAutoDisableIfNeeded() }
        }
    }

    private func updateIsProbing(_ probing: Bool) async {
        await MainActor.run { isProbing = probing }
    }

    private func trimmedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
