import os

/// 统一日志入口（T3-3）：非关键路径的静默失败（`try?`）在此分类留痕。
/// Console.app / log stream 按 subsystem 过滤：
/// `log stream --predicate 'subsystem == "com.fryfrog.hub"'`
enum AppLog {
    /// API 请求、认证、偏好同步等网络链路
    static let networking = Logger(subsystem: "com.fryfrog.hub", category: "networking")
    /// 封面下载、磁盘缓存、降采样解码
    static let image = Logger(subsystem: "com.fryfrog.hub", category: "image")
    /// Keychain、UserDefaults、音乐缓存与元数据文件
    static let storage = Logger(subsystem: "com.fryfrog.hub", category: "storage")

    /// 私有辅助：统一插值脱敏（当前仅透传，预留收敛点）
    static func describe(_ error: Error) -> String {
        String(describing: error)
    }
}
