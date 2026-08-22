import XCTest
@testable import FryfrogHub

/// T3-2：APIClient 内外网切换（requestWithFallback）、isConnectionFailure 判定、
/// 401/403 全局 handler 注入的行为测试。
///
/// isConnectionFailure 为私有实现，经其外部可观测行为覆盖：
/// - 连接级失败（URLError 映射为 httpError(-1)）→ 触发备选地址重试
/// - 业务级失败（如 500/404）→ 不触发切换，原样抛出
private struct Ping: Codable {
    let ok: Bool
}

final class APIClientFallbackTests: XCTestCase {
    private var mockServer: MockServerConnection!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        mockServer = MockServerConnection()
        mockServer.baseURLValue = URL(string: "http://primary.test")
        mockServer.effectiveModeValue = .public
    }

    override func tearDown() {
        StubURLProtocol.reset()
        mockServer = nil
        super.tearDown()
    }

    /// 经 URLProtocol 桩构造的客户端
    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return APIClient(server: mockServer, sessionConfiguration: config)
    }

    // MARK: - 内外网切换

    /// 主地址连接失败 + 备选成功 → 返回备选结果并切换生效模式
    func test_fallback_switchesToAlternateOnPrimaryConnectionFailure() async throws {
        mockServer.alternateURLStringValue = "http://alt.test"
        StubURLProtocol.setBehavior(.init(outcome: .failure(.cannotConnectToHost)), for: "primary.test")
        StubURLProtocol.setBehavior(.init(outcome: .success(200, #"{"ok":true}"#)), for: "alt.test")

        let ping: Ping = try await makeClient().request("/api/v1/ping")

        XCTAssertTrue(ping.ok)
        XCTAssertEqual(StubURLProtocol.requestedHosts, ["primary.test", "alt.test"])
        // 公网失败切到备选（局域网）
        XCTAssertEqual(mockServer.setActiveModeCalls, [.lan])
    }

    /// 主备均连接失败 → 抛出原始错误且不切换
    func test_fallback_throwsOriginalErrorWhenBothFail() async {
        mockServer.alternateURLStringValue = "http://alt.test"
        StubURLProtocol.setBehavior(.init(outcome: .failure(.timedOut)), for: "primary.test")
        StubURLProtocol.setBehavior(.init(outcome: .failure(.cannotConnectToHost)), for: "alt.test")

        do {
            let _: Ping = try await makeClient().request("/api/v1/ping")
            XCTFail("应抛出错误")
        } catch {
            guard case APIError.httpError(let statusCode, _) = error else {
                return XCTFail("期望 httpError(-1)，实际 \(error)")
            }
            XCTAssertEqual(statusCode, -1)
        }
        XCTAssertEqual(StubURLProtocol.requestedHosts, ["primary.test", "alt.test"])
        XCTAssertTrue(mockServer.setActiveModeCalls.isEmpty)
    }

    /// 业务级失败（500）→ 不尝试备选地址，直接抛出
    func test_noFallbackOnBusinessError() async throws {
        mockServer.alternateURLStringValue = "http://alt.test"
        StubURLProtocol.setBehavior(.init(outcome: .success(500, #"{"message":"boom"}"#)), for: "primary.test")

        do {
            let _: Ping = try await makeClient().request("/api/v1/ping")
            XCTFail("应抛出错误")
        } catch {
            guard case APIError.httpError(let statusCode, _) = error else {
                return XCTFail("期望 httpError(500)，实际 \(error)")
            }
            XCTAssertEqual(statusCode, 500)
        }
        XCTAssertEqual(StubURLProtocol.requestedHosts, ["primary.test"])
        XCTAssertTrue(mockServer.setActiveModeCalls.isEmpty)
    }

    /// 未配置备选地址 → 仅请求主地址一次
    func test_noFallbackWhenAlternateNotConfigured() async {
        StubURLProtocol.setBehavior(.init(outcome: .failure(.cannotFindHost)), for: "primary.test")

        do {
            let _: Ping = try await makeClient().request("/api/v1/ping")
            XCTFail("应抛出错误")
        } catch { /* 期望路径 */ }

        XCTAssertEqual(StubURLProtocol.requestedHosts, ["primary.test"])
        XCTAssertTrue(mockServer.setActiveModeCalls.isEmpty)
    }

    // MARK: - 401/403 全局 handler

    /// 业务接口返回 401 → 注入的 unauthorizedHandler 被触发
    func test_unauthorizedHandlerFiresOn401() async throws {
        StubURLProtocol.setBehavior(.init(outcome: .success(401, #"{"message":"expired"}"#)), for: "primary.test")

        let client = makeClient()
        let unauthorized = FlagBox()
        await client.setUnauthorizedHandler { unauthorized.set() }
        await client.setForbiddenHandler {}

        do {
            let _: Ping = try await client.request("/api/v1/secure")
            XCTFail("应抛出错误")
        } catch {
            guard case APIError.httpError(let statusCode, _) = error else {
                return XCTFail("期望 httpError(401)，实际 \(error)")
            }
            XCTAssertEqual(statusCode, 401)
        }
        XCTAssertTrue(unauthorized.isSet, "401 应触发 unauthorizedHandler")
    }

    /// 认证接口自身的 401（登录密码错误等）不触发全局登出
    func test_unauthorizedHandlerSkippedForAuthPaths() async throws {
        StubURLProtocol.setBehavior(.init(outcome: .success(401, #"{"message":"bad credentials"}"#)), for: "primary.test")

        let client = makeClient()
        let unauthorized = FlagBox()
        await client.setUnauthorizedHandler { unauthorized.set() }

        do {
            let _: LoginResponse = try await client.request("/api/v1/auth/login")
            XCTFail("应抛出错误")
        } catch { /* 期望路径 */ }

        XCTAssertFalse(unauthorized.isSet, "认证接口 401 不应触发全局登出")
    }

    /// 业务接口返回 403 → forbiddenHandler 触发、unauthorizedHandler 不触发（保留登录态）
    func test_forbiddenHandlerFiresOn403() async throws {
        StubURLProtocol.setBehavior(.init(outcome: .success(403, #"{"message":"forbidden"}"#)), for: "primary.test")

        let client = makeClient()
        let unauthorized = FlagBox()
        let forbidden = FlagBox()
        await client.setUnauthorizedHandler { unauthorized.set() }
        await client.setForbiddenHandler { forbidden.set() }

        do {
            let _: Ping = try await client.request("/api/v1/admin/panel")
            XCTFail("应抛出错误")
        } catch { /* 期望路径 */ }

        XCTAssertFalse(unauthorized.isSet)
        XCTAssertTrue(forbidden.isSet)
    }
}
