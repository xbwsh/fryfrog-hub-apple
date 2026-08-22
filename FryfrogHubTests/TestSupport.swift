import Foundation
@testable import FryfrogHub

/// T3-2：线程安全的布尔旗标（异步回调内置位、测试线程读取）
final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }
}

/// T3-2：按主机名路由的确定性网络桩。
/// 经 URLSessionConfiguration.protocolClasses 注入，无需真实网络即可模拟
/// 成功响应（任意状态码）与连接级失败（URLError），驱动 APIClient 的
/// 内外网切换 / isConnectionFailure / 401-403 分支测试。
final class StubURLProtocol: URLProtocol {
    struct Behavior {
        enum Outcome {
            /// 返回指定状态码与 JSON 体
            case success(Int, String)
            /// 以 URLError(code) 模拟连接级失败（超时/无法连上主机等）
            case failure(URLError.Code)
        }
        let outcome: Outcome
    }

    /// host → 行为表；未登记的主机一律返回 unsupportedURL 失败
    nonisolated(unsafe) static var behaviors: [String: Behavior] = [:]
    /// 已请求的主机序列（顺序敏感，断言"是否尝试过备选地址"用）
    nonisolated(unsafe) static var requestedHosts: [String] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        behaviors = [:]
        requestedHosts = []
        lock.unlock()
    }

    static func recordHost(_ host: String) {
        lock.lock()
        requestedHosts.append(host)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recordHost(host)
        guard let behavior = Self.lockedBehavior(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch behavior.outcome {
        case .success(let statusCode, let body):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    private static func lockedBehavior(for host: String) -> Behavior? {
        lock.lock()
        defer { lock.unlock() }
        return behaviors[host]
    }

    static func setBehavior(_ behavior: Behavior?, for host: String) {
        lock.lock()
        defer { lock.unlock() }
        behaviors[host] = behavior
    }
}

/// T3-2：ServerConnection 协议替身——可配置主备地址与生效模式，
/// 并记录 setActiveMode 调用序列供断言切换行为
final class MockServerConnection: ServerConnectionProtocol {
    var effectiveModeValue: ServerConnectionMode = .public
    var baseURLValue: URL?
    var activeURLStringValue = ""
    var alternateURLStringValue: String?
    var probeLANResult = false

    private(set) var setActiveModeCalls: [ServerConnectionMode] = []

    var effectiveMode: ServerConnectionMode { effectiveModeValue }
    var baseURL: URL? { baseURLValue }
    var activeURLString: String { activeURLStringValue }

    func urlString(for mode: ServerConnectionMode) -> String? { nil }
    func alternateURLString(for mode: ServerConnectionMode) -> String? { alternateURLStringValue }
    func alternateMode(for mode: ServerConnectionMode) -> ServerConnectionMode {
        mode == .lan ? .public : .lan
    }
    func imageURL(for path: String?) -> URL? { nil }
    func setActiveMode(_ mode: ServerConnectionMode) async {
        setActiveModeCalls.append(mode)
    }
    func probeLAN(timeout: TimeInterval) async -> Bool { probeLANResult }
    func refreshActiveMode() async {}
}
