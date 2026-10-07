import SwiftUI

// MARK: - 用户管理（ADMIN）

/// 用户列表：创建/编辑/删除/重置密码
struct UsersManagementView: View {
    @State private var auth = AuthService.shared
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var editingUser: User?
    @State private var userToDelete: User?
    @State private var userToReset: User?
    @State private var resetPassword = ""
    @State private var showResetAlert = false
    @State private var accessUser: User?

    private var me: User? { auth.currentUser }

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                ContentUnavailableView(
                    "暂无用户",
                    systemImage: "person.2.slash",
                    description: Text("点右上角 + 创建用户")
                )
            } else {
                List {
                    ForEach(users) { user in
                        UserRow(user: user, isSelf: user.id == me?.id) {
                            editingUser = user
                        } onDelete: {
                            userToDelete = user
                        } onResetPassword: {
                            resetPassword = ""
                            userToReset = user
                            showResetAlert = true
                        } onToggle: {
                            Task { await toggleUser(user) }
                        } onManageLibraries: {
                            accessUser = user
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("用户管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("创建用户")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingCreate) {
            UserEditView(mode: .create) { Task { await load() } }
        }
        .sheet(item: $editingUser) { user in
            UserEditView(mode: .edit(user)) { Task { await load(); await auth.refreshCurrentUser() } }
        }
        .sheet(item: $accessUser) { user in
            LibraryAccessView(user: user) {}
        }
        .confirmationDialog(
            "删除用户「\(userToDelete?.username ?? "")」？",
            isPresented: Binding(
                get: { userToDelete != nil },
                set: { if !$0 { userToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let user = userToDelete { Task { await deleteUser(user) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后该用户将无法登录")
        }
        .alert("重置密码 \(userToReset?.username ?? "")", isPresented: $showResetAlert) {
            SecureField("新密码（至少 8 位）", text: $resetPassword)
            Button("重置") {
                if let user = userToReset { Task { await resetPassword(user) } }
            }
            Button("取消", role: .cancel) { userToReset = nil }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await auth.fetchUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleUser(_ user: User) async {
        do {
            try await auth.updateUser(user.id, request: UpdateUserRequest(enabled: user.enabled != true))
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteUser(_ user: User) async {
        guard user.id != me?.id else {
            errorMessage = "不能删除当前登录的账号"
            return
        }
        do {
            try await auth.deleteUser(user.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetPassword(_ user: User) async {
        do {
            try await auth.resetUserPassword(user.id, newPassword: resetPassword)
            resetPassword = ""
            userToReset = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 用户行：头像/昵称/账号/角色 + 启用开关 + 操作菜单
struct UserRow: View {
    let user: User
    let isSelf: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onResetPassword: () -> Void
    var onToggle: () -> Void
    var onManageLibraries: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let avatar = user.avatar {
                ServerImageView(path: avatar)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.subheadline.weight(.medium))
                    CapsuleTag(user.roleText, color: user.isAdmin ? .purple : .secondary)
                    if isSelf {
                        CapsuleTag("我", color: .blue)
                    }
                }
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isSelf {
                Toggle("", isOn: Binding(
                    get: { user.enabled != false },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
            }

            Menu {
                Button { onEdit() } label: { Label("编辑", systemImage: "square.and.pencil") }
                Button { onResetPassword() } label: { Label("重置密码", systemImage: "key") }
                Button { onManageLibraries() } label: { Label("媒体库授权", systemImage: "folder.badge.gearshape") }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(isSelf)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.09), in: Circle())
                    .contentShape(Rectangle())
            }
        }
        .opacity(user.enabled == false && !isSelf ? 0.55 : 1)
    }
}

struct CapsuleTag: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
