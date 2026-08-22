import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingFailed(Error)
    case unauthorized
    /// 连续失败过多，账号临时锁定
    case accountLocked(retryAfterSeconds: Int?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效"
        case .invalidResponse:
            return "服务器返回无效响应"
        case .httpError(let code, let message):
            if code == 403 {
                return "无操作权限"
            }
            if code == 401 {
                return message?.isEmpty == false ? message : "账号或密码错误"
            }
            return message?.isEmpty == false ? message : "请求失败（HTTP \(code)）"
        case .decodingFailed:
            return "数据解析失败"
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .accountLocked(let retryAfter):
            if let retryAfter {
                let minutes = max(1, Int(ceil(Double(retryAfter) / 60)))
                return "登录失败次数过多，账号已锁定，请 \(minutes) 分钟后再试"
            }
            return "登录失败次数过多，账号暂时锁定，请稍后再试"
        }
    }
}
