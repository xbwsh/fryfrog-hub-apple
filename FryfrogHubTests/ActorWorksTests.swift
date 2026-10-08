import XCTest
@testable import FryfrogHub

/// 演员作品接口（GET /api/v1/video/actor/{actorId}/works）对接测试。
/// 返回 PageResponse<SeriesListDTO>：系列聚合为 type="series"、独立视频为 type="standalone"。
/// 关键约定：演员存在但无作品 → 200 空列表；演员不存在 → 404。
/// 前端必须按 HTTP 状态码区分，不能只看 success。
final class ActorWorksTests: XCTestCase {
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

    /// 经 URLProtocol 桩构造的 Service（依赖注入，不走真实网络）
    /// VideoService 为 @MainActor，本类构造与用例均切到主线程域
    @MainActor
    private func makeService() -> VideoService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let client = APIClient(server: mockServer, sessionConfiguration: config)
        return VideoService(client: client, server: mockServer)
    }

    /// 有内容（HTTP 200）：系列与独立视频混合、按系列聚合、分页信息完整
    @MainActor func test_worksWithContent() async throws {
        StubURLProtocol.setBehavior(.init(outcome: .success(200, """
        {
          "success": true,
          "data": {
            "content": [
              { "id": 900, "type": "series", "title": "流浪地球系列", "mediaType": "tv", "year": 2019, "numberOfSeasons": 2, "episodeCount": 20 },
              { "id": 12, "type": "standalone", "title": "战狼", "year": 2017 }
            ],
            "page": 0, "size": 20, "totalElements": 2, "totalPages": 1
          }
        }
        """)), for: "primary.test")

        let service = makeService()
        let page = try await service.fetchActorWorks(actorId: 1, page: 0, size: 20)

        XCTAssertEqual(page.content?.count, 2)
        XCTAssertEqual(page.content?.first?.id, 900)
        XCTAssertEqual(page.content?.first?.type, "series")
        XCTAssertEqual(page.content?.first?.isTV, true)
        XCTAssertEqual(page.content?.first?.episodeCount, 20)
        XCTAssertEqual(page.content?.last?.type, "standalone")
        XCTAssertEqual(page.content?.last?.isStandalone, true)
        XCTAssertEqual(page.totalElements, 2)
        XCTAssertEqual(page.totalPages, 1)
    }

    /// 无内容（HTTP 200）：不抛错，返回空 content
    @MainActor func test_worksEmptyList() async throws {
        StubURLProtocol.setBehavior(.init(outcome: .success(200, """
        {
          "success": true,
          "data": { "content": [], "page": 0, "size": 20, "totalElements": 0, "totalPages": 0 }
        }
        """)), for: "primary.test")

        let service = makeService()
        let page = try await service.fetchActorWorks(actorId: 2, page: 0, size: 20)

        XCTAssertEqual(page.content?.count, 0)
        XCTAssertEqual(page.totalPages, 0)
    }

    /// 演员不存在（HTTP 404）：抛 httpError(404)，message 透传后端提示
    @MainActor func test_actorNotFoundThrows404() async {
        StubURLProtocol.setBehavior(.init(outcome: .success(404, """
        { "success": false, "message": "VideoActor not found with id: 999" }
        """)), for: "primary.test")

        let service = makeService()
        do {
            _ = try await service.fetchActorWorks(actorId: 999)
            XCTFail("演员不存在应抛出 404")
        } catch {
            guard case APIError.httpError(let code, let message) = error else {
                return XCTFail("期望 httpError(404)，实际 \(error)")
            }
            XCTAssertEqual(code, 404)
            XCTAssertEqual(message, "VideoActor not found with id: 999")
        }
    }
}