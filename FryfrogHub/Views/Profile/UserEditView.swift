import SwiftUI

// MARK: - 创建/编辑用户

struct UserEditView: View {
    enum Mode {
        case create
        case edit(User)
    }

    let mode: Mode
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var nickname = ""
    @State private var password = ""
    @State private var role = "USER"
    @State private var enabled = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let auth = AuthService.shared

    private var editingUser: User? {
        if case .edit(let user) = mode { return user }
        return nil
    }

    private var isEdit: Bool { editingUser != nil }

    init(mode: Mode, onSaved: @escaping () -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        if case .edit(let user) = mode {
            _username = State(initialValue: user.username)
            _nickname = State(initialValue: user.nickname ?? "")
            _role = State(initialValue: user.role ?? "USER")
            _enabled = State(initialValue: user.enabled ?? true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isEdit ? "账号信息" : "基本信息") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isEdit)
                        .opacity(isEdit ? 0.6 : 1)
                    TextField("昵称（选填）", text: $nickname)
                    if !isEdit {
                        SecureField("密码（至少 8 位）", text: $password)
                    }
                }

                Section {
                    Picker("角色", selection: $role) {
                        Text("普通用户").tag("USER")
                        Text("管理员").tag("ADMIN")
                    }
                    Toggle("启用", isOn: $enabled)
                        .disabled(isSelfEditingEnabled)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(isEdit ? "编辑用户" : "创建用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button(isEdit ? "保存" : "创建") {
                            Task { await save() }
                        }
                        .disabled(!canSubmit)
                    }
                }
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
    }

    /// 自身账号不允许在此把自己禁用
    private var isSelfEditingEnabled: Bool {
        isEdit && editingUser?.id == auth.currentUser?.id
    }

    private var canSubmit: Bool {
        if isEdit {
            return !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 8
    }

    private func save() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if let user = editingUser {
                try await auth.updateUser(
                    user.id,
                    request: UpdateUserRequest(
                        nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                        avatar: nil,
                        role: role,
                        enabled: enabled
                    )
                )
            } else {
                try await auth.createUser(CreateUserRequest(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: role
                ))
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
