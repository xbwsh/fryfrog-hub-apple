import SwiftUI

// MARK: - 修改密码

/// 修改自己的密码（成功后建议重新登录）
struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let auth = AuthService.shared

    private var canSubmit: Bool {
        !oldPassword.isEmpty
            && newPassword.count >= 8
            && !confirmPassword.isEmpty
    }

    var body: some View {
        Form {
            Section {
                SecureField("当前密码", text: $oldPassword)
                SecureField("新密码（至少 8 位）", text: $newPassword)
                SecureField("确认新密码", text: $confirmPassword)
            } footer: {
                if !confirmPassword.isEmpty, newPassword != confirmPassword {
                    Text("两次输入的新密码不一致")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("修改密码")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canSubmit || isLoading)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("修改密码")
        .navigationBarTitleDisplayMode(.inline)
        .alert("密码修改成功", isPresented: $showSuccess) {
            Button("确定") {
                dismiss()
                Task { await auth.logout() }
            }
        } message: {
            Text("为安全起见将退出登录，请使用新密码重新登录")
        }
        .alert("修改失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard !isLoading else { return }
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的新密码不一致"
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await auth.changeOwnPassword(oldPassword: oldPassword, newPassword: newPassword)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
