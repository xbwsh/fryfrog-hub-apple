import Foundation

actor APIClient {
    static let shared = APIClient()

    private var token: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private init() {}

    func setToken(_ token: String?) {
        self.token = token
    }

    var currentToken: String? { token }

    /// token 被服务器拒绝（401）时通知持有者清除会话（由 AuthService 注入）
    private var unauthorizedHandler: (() async -> Void)?
    /// 无权限（403）时通知全局提示（由 AuthService 注入）
    private var forbiddenHandler: (() async -> Void)?

    func setUnauthorizedHandler(_ handler: @escaping () async -> Void) {
        self.unauthorizedHandler = handler
    }

    func setForbiddenHandler(_ handler: @escaping () async -> Void) {
        self.forbiddenHandler = handler
    }

    /// 发起请求并解码为指定类型
    /// 局域网/公网互备：当前地址连不通（DNS/拒绝/超时等连接级错误）时，
    /// 自动尝试备选地址一次；若备选成功则切换生效连接并持久化。
    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: AnyEncodable? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        do {
            return try await requestWithFallback(path, method: method, body: body, queryItems: queryItems)
        } catch let error {
            await notifyUnauthorizedIfNeeded(path: path, error: error)
            await notifyForbiddenIfNeeded(path: path, error: error)
            throw error
        }
    }

    private func requestWithFallback<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: AnyEncodable? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let server = ServerConnection.shared
        guard let baseURL = server.baseURL else {
            throw APIError.invalidURL
        }
        let mode = server.effectiveMode

        do {
            return try await perform(path, method: method, body: body, queryItems: queryItems, baseURL: baseURL)
        } catch let originalError {
            guard isConnectionFailure(originalError),
                  let alternateString = server.alternateURLString(for: mode),
                  let alternateURL = URL(string: alternateString),
                  alternateURL != baseURL else {
                throw originalError
            }
            do {
                let result: T = try await perform(path, method: method, body: body, queryItems: queryItems, baseURL: alternateURL)
                await server.setActiveMode(server.alternateMode(for: mode))
                return result
            } catch {
                throw originalError
            }
        }
    }

    /// 业务请求返回 401 且非认证接口时，通知登录会话已失效（全局自动登出）
    private func notifyUnauthorizedIfNeeded(path: String, error: Error) async {
        guard !path.contains("/auth/login"), !path.contains("/auth/logout") else { return }
        if case APIError.httpError(let statusCode, _) = error, statusCode == 401 {
            await unauthorizedHandler?()
        }
    }

    /// 业务请求返回 403（角色/权限不足）时触发全局"无操作权限"提示（不影响登录态）
    private func notifyForbiddenIfNeeded(path: String, error: Error) async {
        guard !path.contains("/auth/login"), !path.contains("/auth/logout") else { return }
        if case APIError.httpError(let statusCode, _) = error, statusCode == 403 {
            await forbiddenHandler?()
        }
    }

    /// 发起请求但不关心返回值
    func requestVoid(
        _ path: String,
        method: String = "GET",
        body: AnyEncodable? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws {
        let _: EmptyResponse = try await request(path, method: method, body: body, queryItems: queryItems)
    }

    /// 使用指定基础地址执行一次请求
    private func perform<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: AnyEncodable? = nil,
        queryItems: [URLQueryItem] = [],
        baseURL: URL
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path += path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                urlRequest.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw APIError.decodingFailed(error)
            }
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            throw map(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 429,
               let retryAfterSeconds = parseLockout(from: data) {
                throw APIError.accountLocked(retryAfterSeconds: retryAfterSeconds)
            }
            let message = extractErrorMessage(from: data)
            throw APIError.httpError(statusCode: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    /// 连接级失败（含已映射为 httpError(-1) 的 URL 错误）才触发公网/局域网切换
    private func isConnectionFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
                 .timedOut, .networkConnectionLost, .cannotLoadFromNetwork,
                 .internationalRoamingOff, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        if case APIError.httpError(let statusCode, _) = error, statusCode == -1 {
            return true
        }
        return false
    }

    private func map(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet:
            return APIError.httpError(statusCode: -1, message: "网络连接不可用")
        case .cannotConnectToHost, .cannotFindHost:
            return APIError.httpError(statusCode: -1, message: "无法连接到服务器，请检查地址")
        case .timedOut:
            return APIError.httpError(statusCode: -1, message: "连接服务器超时")
        default:
            return APIError.httpError(statusCode: -1, message: error.localizedDescription)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        struct ServerMessage: Decodable {
            let message: String?
            let data: String?
        }
        guard let decoded = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            return nil
        }
        return decoded.message ?? decoded.data
    }

    /// 账号锁定响应：`{"message":..., "retryAfterSeconds": N}`，返回重试秒数
    private func parseLockout(from data: Data) -> Int? {
        struct LockInfo: Decodable {
            let retryAfterSeconds: Int?
        }
        return (try? JSONDecoder().decode(LockInfo.self, from: data))?.retryAfterSeconds
    }
}

struct EmptyResponse: Decodable {}