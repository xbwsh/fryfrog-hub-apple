import SwiftUI

struct LoginView: View {
    @State private var viewModel = LoginViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case server, lan, port, username, password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 24)

                // 品牌区（应用图标与标题一行）
                HStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fryfrog Hub")
                            .font(.largeTitle.bold())
                        Text("连接你的媒体库服务器")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

            // 表单
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("公网服务器地址")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("IP 或域名，如 192.168.1.100", text: $viewModel.serverHost)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .server)
                        .onSubmit { focusedField = .lan }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                        )
                    Text("只填主机地址，协议与端口在下方单独设置")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("局域网地址（选填）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("如 192.168.1.100", text: $viewModel.lanHost)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .lan)
                        .onSubmit { focusedField = .port }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                        )
                    Text("选填；与公网共用上方协议与端口，局域网优先")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // 协议 + 端口（两控件放入同高 44pt 容器，视觉等高）
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("协议")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Picker("协议", selection: $viewModel.scheme) {
                            Text("http").tag("http")
                            Text("https").tag("https")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(height: 44)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("端口")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("20058", text: $viewModel.port)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .port)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.quaternary)
                            )
                    }
                    .frame(maxWidth: 130)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("用户名")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("admin", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("密码")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SecureField("输入密码", text: $viewModel.password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .password)
                        .onSubmit { submit() }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                        )
                }

                Button {
                    submit()
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit || viewModel.isLoading)
            }
            .frame(maxWidth: 360)

                Spacer().frame(height: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .alert(
            "登录失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func submit() {
        Task { await viewModel.login() }
    }
}

#Preview {
    LoginView()
}
