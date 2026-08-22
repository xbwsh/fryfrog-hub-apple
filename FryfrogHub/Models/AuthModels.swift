import Foundation

/// 服务端统一响应包装：`{ "success": bool, "message": str?, "data": T? }`
struct ApiResponse<T: Decodable>: Decodable {
    let success: Bool
    let message: String?
    let data: T?
}

// MARK: - 用户

/// 用户信息（登录响应 / auth/me / 用户管理共用）
struct User: Codable, Identifiable, Hashable {
    let id: Int64
    let username: String
    let nickname: String?
    let avatar: String?
    let role: String?
    let enabled: Bool?
    let createdAt: String?
    let lastLoginAt: String?

    var displayName: String { (nickname?.isEmpty == false ? nickname! : username) }

    var isAdmin: Bool { role?.uppercased() == "ADMIN" }

    var roleText: String { isAdmin ? "管理员" : "普通用户" }
}

/// 创建用户：`{username, password, nickname, role}`
struct CreateUserRequest: Encodable {
    var username: String
    var password: String
    var nickname: String?
    var role: String?
}

/// 更新用户：`{nickname, avatar, role, enabled}`
struct UpdateUserRequest: Encodable {
    var nickname: String?
    var avatar: String?
    var role: String?
    var enabled: Bool?
}

/// 修改自己的密码：`{oldPassword, newPassword}`
struct ChangePasswordRequest: Encodable {
    var oldPassword: String
    var newPassword: String
}

/// 管理员重置密码：`{newPassword}`
struct ResetPasswordRequest: Encodable {
    var newPassword: String
}

// MARK: - 认证响应

/// `POST /api/v1/auth/login` 返回的原始结构（未走统一包装）
struct LoginResponse: Decodable {
    let success: Bool
    let token: String?
    let message: String?
    let user: User?
}

/// `GET /api/v1/auth/me` 返回结构
struct MeResponse: Decodable {
    let success: Bool
    let user: User?
}

/// `GET /api/v1/auth/status` 返回结构
struct AuthStatusResponse: Decodable {
    let enabled: Bool
}

/// 通用"无内容"响应（用于只关心请求是否成功的 POST/PUT）
struct ApiResponseNoContent: Decodable {
    let success: Bool?
    let message: String?
}
