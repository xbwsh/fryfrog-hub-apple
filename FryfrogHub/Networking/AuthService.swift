import Foundation
import Observation
import UIKit

@Observable
final class AuthService {
    static let shared = AuthService()

    private let client: any APIClientProtocol
    /// 预留：与其它 Service 统一注入契约（当前方法未直接使用）
    private let server: any ServerConnectionProtocol
    private let tokenStore = TokenStore.shared
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastUsername = "auth.lastUsername"
    }

    private(set) var isAuthenticated = false
    private(set) var currentUser: User?

    /// T3-1：默认单例入口；测试可注入协议替身
    init(client: any APIClientProtocol = APIClient.shared, server: any ServerConnectionProtocol = ServerConnection.shared) {
        self.client = client
        self.server = server
        // 任何业务请求返回 401 时，全局清除会话回到登录页
        Task {
            await client.setUnauthorizedHandler { [weak self] in
                await self?.handleServerRejected()
            }
            // 403 权限不足时，全局提示"无操作权限"（保留登录态）
            await client.setForbiddenHandler {
                await MainActor.run { GlobalNotice.shared.show("无操作权限") }
            }
        }
    }

    /// token 被服务器拒绝（401）：清除本地会话，回到登录页
    private func handleServerRejected() async {
        tokenStore.delete()
        await client.setToken(nil)
        await MainActor.run {
            currentUser = nil
            isAuthenticated = false
        }
    }

    /// 上次登录用的用户名（登录页预填，默认 admin）
    var lastUsername: String {
        defaults.string(forKey: Keys.lastUsername) ?? "admin"
    }

    /// 启动时恢复会话：本地有 token 则拉取当前用户（/auth/me）
    /// token 已被服务器吊销时（401）自动清除会话；网络异常时保留会话待重试
    func restoreSession() async {
        // 确保全局 401/403 处理已注册，避免 init 中 Task 竞态
        await client.setUnauthorizedHandler { [weak self] in await self?.handleServerRejected() }
        await client.setForbiddenHandler { await MainActor.run { GlobalNotice.shared.show("无操作权限") } }
        guard let token = tokenStore.read() else { return }
        await client.setToken(token)
        do {
            let response: ApiResponse<User> = try await client.request("/api/v1/auth/me")
            currentUser = response.data
            isAuthenticated = true
            // 已登录则同步云端偏好（失败静默，保留本地缓存）
            await PreferenceSync.shared.fetch()
        } catch {
            currentUser = nil
            isAuthenticated = false
            if isServerRejectingToken(error) {
                tokenStore.delete()
                await client.setToken(nil)
            }
        }
    }

    /// 登录：用户名 + 密码
    func login(username: String, password: String) async throws {
        let body = AnyEncodable(["username": username, "password": password])
        let response: LoginResponse = try await client.request(
            "/api/v1/auth/login",
            method: "POST",
            body: body
        )
        guard response.success else {
            throw APIError.httpError(statusCode: 401, message: response.message)
        }
        guard let data = response.data else {
            throw APIError.unauthorized
        }
        let token = data.token
        guard !token.isEmpty else {
            throw APIError.unauthorized
        }
        tokenStore.save(token)
        await client.setToken(token)
        currentUser = data.user
        defaults.set(username, forKey: Keys.lastUsername)
        isAuthenticated = true
        // 登录成功拉取该账号云端偏好（失败静默，保留本地）
        await PreferenceSync.shared.fetch()
    }

    /// 登出
    func logout() async {
        let serverLogout = Task {
            do {
                _ = try await client.requestVoid("/api/v1/auth/logout", method: "POST")
            } catch {
                // 服务端登出失败不阻断本地清理（token 已作废场景常见），仅留痕
                AppLog.networking.warning("服务端登出失败（本地会话照常清除）: \(AppLog.describe(error))")
            }
        }
        tokenStore.delete()
        await client.setToken(nil)
        currentUser = nil
        isAuthenticated = false
        // 本地状态先切回登录页，避免服务器不可达时等待请求超时。
        await serverLogout.value
    }

    /// 刷新当前用户信息（如修改资料后）
    func refreshCurrentUser() async {
        guard isAuthenticated else { return }
        currentUser = await fetchMe()
    }

    private func fetchMe() async -> User? {
        do {
            let response: ApiResponse<User> = try await client.request("/api/v1/auth/me")
            return response.data
        } catch {
            AppLog.networking.warning("刷新当前用户失败: \(AppLog.describe(error))")
            return nil
        }
    }

    private func isServerRejectingToken(_ error: Error) -> Bool {
        if case APIError.httpError(let statusCode, _) = error, statusCode == 401 {
            return true
        }
        return false
    }

    // MARK: - 账户

    /// 修改自己的密码（token 不失效，但建议提示重新登录）
    func changeOwnPassword(oldPassword: String, newPassword: String) async throws {
        let body = AnyEncodable(ChangePasswordRequest(oldPassword: oldPassword, newPassword: newPassword))
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/users/me/password",
            method: "PUT",
            body: body
        )
    }

    // MARK: - 用户管理（ADMIN）

    func fetchUsers() async throws -> [User] {
        let response: ApiResponse<[User]> = try await client.request("/api/v1/users")
        return response.data ?? []
    }

    func createUser(_ request: CreateUserRequest) async throws {
        let _: ApiResponse<User> = try await client.request(
            "/api/v1/users",
            method: "POST",
            body: AnyEncodable(request)
        )
    }

    func updateUser(_ id: Int64, request: UpdateUserRequest) async throws {
        let _: ApiResponse<User> = try await client.request(
            "/api/v1/users/\(id)",
            method: "PUT",
            body: AnyEncodable(request)
        )
    }

    func deleteUser(_ id: Int64) async throws {
        let _: ApiResponse<[String: String]> = try await client.request(
            "/api/v1/users/\(id)",
            method: "DELETE"
        )
    }

    func resetUserPassword(_ id: Int64, newPassword: String) async throws {
        let body = AnyEncodable(ResetPasswordRequest(newPassword: newPassword))
        let _: ApiResponseNoContent = try await client.request(
            "/api/v1/users/\(id)/password",
            method: "PUT",
            body: body
        )
    }

    /// 查询用户被分配的媒体库 ID（ADMIN）
    func fetchUserLibraries(id: Int64) async throws -> [Int64] {
        let response: ApiResponse<[Int64]> = try await client.request("/api/v1/users/\(id)/libraries")
        return response.data ?? []
    }

    /// 分配/修改用户的媒体库授权（ADMIN；空数组 = 收回全部）
    func assignLibraries(to id: Int64, libraryIds: [Int64]) async throws {
        let body = AnyEncodable(["libraryIds": libraryIds])
        let _: ApiResponse<[Int64]> = try await client.request(
            "/api/v1/users/\(id)/libraries",
            method: "PUT",
            body: body
        )
    }

    // MARK: - 用户偏好（云同步）

    /// 拉取我的偏好（GET /api/v1/users/me/preferences，返回当前账号全部偏好）
    func fetchPreferences() async throws -> [String: String] {
        let response: ApiResponse<[String: String]> = try await client.request("/api/v1/users/me/preferences")
        return response.data ?? [:]
    }

    /// 全量更新我的偏好（PUT /api/v1/users/me/preferences；value 空串 = 删除该键）
    func updatePreferences(_ prefs: [String: String]) async throws {
        let body = AnyEncodable(["preferences": prefs])
        let _: ApiResponse<[String: String]> = try await client.request(
            "/api/v1/users/me/preferences",
            method: "PUT",
            body: body
        )
    }
}

// MARK: - 用户偏好云同步

/// 「我的」页设置与后端的同步协调器：
/// - 本地 UserDefaults 是事实来源与离线缓存；
/// - 登录成功 / 启动恢复会话后从云端拉取覆盖本地；
/// - 本地变更立即上传（合并并发请求），失败时持久化“未同步”标记；
/// - 有未同步改动时本地优先，防止云端旧值覆盖本地新值（含杀后台重开场景）。
final class PreferenceSync {
    static let shared = PreferenceSync()

    private enum Keys {
        /// 是否有未成功上传到云端的本地变更（持久化，重启/杀后台仍生效）
        static let pending = "prefSync.pending"
    }

    /// 参与云同步的本地键（与 UserDefaults 键保持一致）
    static let syncedKeys = [
        "theme.mode",
        "privacy.isEnabled",
        "decodeMode",
        "subtitlePreference",
    ]

    private let defaults = UserDefaults.standard

    /// 应用云端值时置位，抑制 didSet 触发的重复上传
    private var suppressUpload = false
    private var uploadTask: Task<Void, Never>?

    /// 是否有尚未成功上传到云端的本地变更（跨启动保留）
    private var hasPendingChanges: Bool {
        get { defaults.bool(forKey: Keys.pending) }
        set { defaults.set(newValue, forKey: Keys.pending) }
    }

    private init() {
        // 退后台（含即将被杀）时立即冲刷未上传的偏好
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.flushPending()
            }
        }
    }

    /// 本地设置变更后调用：立即上传（设置均为离散项，无需防抖），并合并并发请求
    func scheduleUpload() {
        Task { @MainActor [weak self] in
            self?.scheduleUploadOnMain()
        }
    }

    @MainActor
    private func scheduleUploadOnMain() {
        guard !suppressUpload, AuthService.shared.isAuthenticated else { return }
        hasPendingChanges = true
        guard uploadTask == nil else { return }  // 已在途中，结束时自动补齐最新状态
        uploadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 循环上传直到本地无未同步变更（失败带小间隔重试，避免空转）
            while self.hasPendingChanges {
                await self.upload()
                if self.hasPendingChanges {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            self.uploadTask = nil
        }
    }

    /// 退后台时冲刷：有未上传变更则立即尝试上传一次
    @MainActor
    private func flushPending() async {
        guard hasPendingChanges else { return }
        await upload()
    }

    /// 用云端值覆盖本地（不触发回传）
    @MainActor
    func apply(_ prefs: [String: String]) {
        suppressUpload = true
        defer { suppressUpload = false }

        if let raw = prefs["theme.mode"], let mode = AppThemeMode(rawValue: raw) {
            ThemeSettings.shared.mode = mode
        }
        if let raw = prefs["privacy.isEnabled"] {
            PrivacySettings.shared.isEnabled = raw == "true"
        }
        if let raw = prefs["decodeMode"], let mode = DecodeMode(rawValue: raw) {
            PlayerSettings.shared.decodeMode = mode
        }
        if let raw = prefs["subtitlePreference"], let data = raw.data(using: .utf8) {
            do {
                PlayerSettings.shared.subtitlePreference = try JSONDecoder().decode(SubtitlePreference.self, from: data)
            } catch {
                AppLog.storage.warning("云端字幕偏好解码失败，保留本地值: \(AppLog.describe(error))")
            }
        }
    }

    /// 启动恢复会话/登录后从云端拉取。
    /// 本地有未同步改动时以本地为准（先补传，不拉取），否则用云端值覆盖本地。
    @MainActor
    func fetch() async {
        guard AuthService.shared.isAuthenticated else { return }
        if hasPendingChanges {
            await upload()
            return
        }
        do {
            let prefs = try await AuthService.shared.fetchPreferences()
            guard !prefs.isEmpty else { return }
            apply(prefs)
        } catch {
            AppLog.networking.warning("拉取云端偏好失败，保留本地值: \(AppLog.describe(error))")
        }
    }

    /// 上传本地全部同步键到云端；成功清除“未同步”标记
    @MainActor
    private func upload() async {
        guard AuthService.shared.isAuthenticated else { return }
        do {
            try await AuthService.shared.updatePreferences(snapshot())
            hasPendingChanges = false
        } catch let error as APIError {
            if case .httpError(let code, _) = error, code == 403 || code == 401 {
                hasPendingChanges = false
                GlobalNotice.shared.show("无操作权限")
                return
            }
            // 其他失败保留标记，稍后重试
        } catch {
            // 失败保留标记，稍后重试
        }
    }

    /// 收集本地设置快照（全量，含全部同步键）
    @MainActor
    private func snapshot() -> [String: String] {
        var prefs: [String: String] = [:]
        prefs["theme.mode"] = ThemeSettings.shared.mode.rawValue
        prefs["privacy.isEnabled"] = PrivacySettings.shared.isEnabled ? "true" : "false"
        prefs["decodeMode"] = PlayerSettings.shared.decodeMode.rawValue
        if let sub = PlayerSettings.shared.subtitlePreference {
            do {
                let data = try JSONEncoder().encode(sub)
                prefs["subtitlePreference"] = String(data: data, encoding: .utf8)
            } catch {
                AppLog.storage.warning("字幕偏好编码失败，本次不上传该项: \(AppLog.describe(error))")
            }
        }
        return prefs
    }
}
