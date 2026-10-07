import XCTest
@testable import FryfrogHub

/// T3-2：ServerConnection 的 probeLAN / refreshActiveMode 分支测试。
/// 使用隔离的 UserDefaults suite 与注入的探测会话（URLProtocol 桩），
/// 不触碰真实网络与全局单例状态。
final class ServerConnectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "T3_2_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        StubURLProtocol.reset()
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// 经桩会话构造探测用的连接配置
    private func makeConnection() -> ServerConnection {
        let conn = ServerConnection(defaults: defaults)
        conn.scheme = "http"
        conn.port = "20058"
        conn.publicHost = "pub.test"
        conn.lanHost = "lan.test"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        conn.lanProbeSession = URLSession(configuration: config)
        return conn
    }

    // MARK: - probeLAN

    func test_probeLAN_returnsTrueWhenReachable() async {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .success(200, "{}")), for: "lan.test")

        let reachable = await conn.probeLAN(timeout: 1)

        XCTAssertTrue(reachable)
    }

    func test_probeLAN_returnsFalseWhenUnreachable() async {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .failure(.timedOut)), for: "lan.test")

        let reachable = await conn.probeLAN(timeout: 1)

        XCTAssertFalse(reachable)
    }

    func test_probeLAN_returnsFalseWithoutLANHost() async {
        let conn = makeConnection()
        conn.lanHost = ""

        let reachable = await conn.probeLAN(timeout: 1)

        XCTAssertFalse(reachable)
    }

    // MARK: - refreshActiveMode

    func test_refreshActiveMode_prefersLANWhenProbeSucceeds() async {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .success(200, "{}")), for: "lan.test")

        await conn.refreshActiveMode()

        XCTAssertEqual(conn.effectiveMode, .lan)
        XCTAssertEqual(conn.activeURLString, "http://lan.test:20058")
    }

    func test_refreshActiveMode_fallsBackToPublicWhenProbeFails() async {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .failure(.cannotConnectToHost)), for: "lan.test")

        await conn.refreshActiveMode()

        XCTAssertEqual(conn.effectiveMode, .public)
        XCTAssertEqual(conn.activeURLString, "http://pub.test:20058")
    }

    func test_refreshActiveMode_forcesPublicWhenNoLANConfigured() async {
        let conn = makeConnection()
        conn.lanHost = ""
        conn.activeMode = .lan

        await conn.refreshActiveMode()

        XCTAssertEqual(conn.effectiveMode, .public)
    }

    // MARK: - 延迟测量

    func test_measureLatency_returnsNonNegativeMillisecondsWhenReachable() async throws {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .success(200, "{}")), for: "lan.test")

        let ms = await conn.measureLatency(for: .lan)

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ms), 0)
    }

    func test_measureLatency_returnsNilWhenUnreachable() async {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .failure(.timedOut)), for: "pub.test")

        let ms = await conn.measureLatency(for: .public)

        XCTAssertNil(ms)
    }

    func test_measureLatency_returnsNilWithoutHost() async {
        let conn = makeConnection()
        conn.publicHost = ""

        let ms = await conn.measureLatency(for: .public)

        XCTAssertNil(ms)
    }

    func test_refreshLatencies_updatesBothConfiguredModes() async {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .success(200, "{}")), for: "lan.test")
        StubURLProtocol.setBehavior(.init(outcome: .success(200, "{}")), for: "pub.test")

        await conn.refreshLatencies()

        XCTAssertNotNil(conn.latency(for: .lan))
        XCTAssertNotNil(conn.latency(for: .public))
        XCTAssertFalse(conn.isMeasuringLatency)
    }

    func test_refreshLatencies_unreachableModeStaysNil() async {
        let conn = makeConnection()
        StubURLProtocol.setBehavior(.init(outcome: .success(200, "{}")), for: "lan.test")
        StubURLProtocol.setBehavior(.init(outcome: .failure(.cannotConnectToHost)), for: "pub.test")

        await conn.refreshLatencies()

        XCTAssertNotNil(conn.latency(for: .lan))
        XCTAssertNil(conn.latency(for: .public))
    }

    // MARK: - effectiveMode / baseURL

    func test_effectiveMode_forcesPublicWithoutLAN() {
        let conn = makeConnection()
        conn.activeMode = .lan
        conn.lanHost = ""

        XCTAssertEqual(conn.effectiveMode, .public)
    }

    func test_baseURL_nilWhenNothingConfigured() {
        let conn = ServerConnection(defaults: defaults)

        XCTAssertNil(conn.baseURL)
    }
}
