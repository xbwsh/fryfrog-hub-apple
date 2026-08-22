import Foundation

/// 基于 actor 的异步计数信号量：以挂起（非阻塞）方式限制并发，
/// 替代 DispatchSemaphore——后者在 Swift 并发的协作线程池上 wait 会占死一个线程，存在优先级反转风险。
///
/// - FIFO 公平：先到先得，无饥饿
/// - 不感知取消：被取消的任务仍会排队，获得许可后由后续操作（如 URLSession）立即抛错退出；
///   许可经 release 归还，不会泄漏
actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// limit 为最大并发数（许可总数）
    init(limit: Int) {
        precondition(limit > 0, "limit 必须 > 0")
        available = limit
    }

    /// 获取一个许可；无空闲时挂起当前任务直至有释放
    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        // 注册等待者（body 同步执行，不存在跨挂起持有状态的问题）
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    /// 归还一个许可；有排队者时许可直接移交队首（available 保持不变）
    func signal() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            available += 1
        }
    }

    /// 获取许可执行 body，任何退出路径都保证归还许可
    func withPermit<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        await wait()
        do {
            let value = try await body()
            signal()
            return value
        } catch {
            signal()
            throw error
        }
    }
}
