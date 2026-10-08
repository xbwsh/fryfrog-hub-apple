import Foundation
import Observation

/// 登录表单状态仅主线程读写（errorMessage/isLoading 与 LoginView 的绑定同线程）
@MainActor
@Observable
final class LoginViewModel {
    /// 协议仅支持 http/https
    var scheme = "http"
    /// 公网主机地址（域名或 IP，不含协议与端口）
    var serverHost = ""
    /// 局域网主机地址（选填，与公网共用协议和端口）
    var lanHost = ""
    /// 端口，默认 20058
    var port = "20058"
    /// 用户名，默认 admin
    var username = "admin"
    var password = ""

    private(set) var isLoading = false
    var errorMessage: String?

    init() {
        let config = ServerConnection.shared
        scheme = config.scheme
        port = config.port
        serverHost = config.publicHost
        lanHost = config.lanHost
        username = AuthService.shared.lastUsername
    }

    /// 密码非空、端口合法且至少填写了一个主机地址才允许提交
    var canSubmit: Bool {
        guard !password.isEmpty, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let lan = lanHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !host.isEmpty || !lan.isEmpty
    }

    func login() async {
        guard !isLoading else { return }
        errorMessage = nil

        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let lan = lanHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty || !lan.isEmpty else {
            errorMessage = "请至少填写公网或局域网地址"
            return
        }
        let portString = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portValue = Int(portString), (1...65535).contains(portValue) else {
            errorMessage = "端口格式不正确（1-65535）"
            return
        }
        guard host.isEmpty || isValid(host: host, port: portValue) else {
            errorMessage = "公网服务器地址格式不正确"
            return
        }
        guard lan.isEmpty || isValid(host: lan, port: portValue) else {
            errorMessage = "局域网地址格式不正确"
            return
        }

        let config = ServerConnection.shared
        config.scheme = scheme
        config.port = portString
        config.publicHost = host
        config.lanHost = lan
        // 清理旧异地组网残留
        if UserDefaults.standard.object(forKey: "server.meshHost") != nil {
            UserDefaults.standard.removeObject(forKey: "server.meshHost")
        }

        // 确定首发连接：局域网通就优先走局域网
        await config.refreshActiveMode()

        isLoading = true
        defer { isLoading = false }

        do {
            try await AuthService.shared.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// IPv6 地址需带方括号，用户直接粘贴裸 IPv6 时自动补齐（T3-5：复用 HostValidator）
    private func isValid(host: String, port: Int) -> Bool {
        HostValidator.isValid(host: host, port: port, scheme: scheme)
    }
}
