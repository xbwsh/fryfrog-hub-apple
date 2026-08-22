import SwiftUI

struct ProfileView: View {
    @State private var service = AuthService.shared
    @State private var connection = ServerConnection.shared
    @Bindable private var privacy = PrivacySettings.shared
    @Bindable private var theme = ThemeSettings.shared
    @Bindable private var playerSettings = PlayerSettings.shared
    @State private var cacheService = MusicCacheService.shared
    @Bindable private var cacheSettings = MusicCacheSettings.shared

    /// 连接状态徽标：当前生效的连接方式 + 颜色圆点
    private var connectionStatusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.hasAnyAddress ? "\(connection.effectiveMode.title)连接" : "未配置")
                    .font(.callout.weight(.semibold))
                if connection.hasLAN {
                    Text("局域网优先，失败自动切公网")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var connectionStatusColor: Color {
        // 连接正常即为绿色：局域网/公网任一成功连接都表示可用，橙色容易误读为异常
        connection.hasAnyAddress ? .green : .gray
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        if let user = service.currentUser, let avatar = user.avatar {
                            ServerImageView(path: avatar)
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 52, height: 52)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(service.currentUser?.displayName ?? "未登录")
                                .font(.headline)
                            if let user = service.currentUser {
                                Text("@\(user.username) · \(user.roleText)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)

                    NavigationLink {
                        ChangePasswordView()
                    } label: {
                        Label("修改密码", systemImage: "key")
                    }

                    if service.currentUser?.isAdmin == true {
                        NavigationLink {
                            UsersManagementView()
                        } label: {
                            Label("用户管理", systemImage: "person.2")
                        }
                    }
                } header: {
                    Text("账户")
                }

                if service.currentUser?.isAdmin == true {
                    Section("管理") {
                        NavigationLink {
                            LibraryView()
                        } label: {
                            Label("媒体库管理", systemImage: "rectangle.stack.fill")
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        connectionStatusBadge
                        Spacer()
                        if connection.hasLAN {
                            Button {
                                Task { await connection.refreshActiveMode() }
                            } label: {
                                if connection.isProbing {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.small)
                            .disabled(connection.isProbing)
                            .accessibilityLabel("重新检测局域网")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前使用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(connection.activeURLString.isEmpty ? "未配置" : connection.activeURLString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)

                    if let publicURL = connection.publicURLString {
                        LabeledContent("公网地址") {
                            Text(publicURL)
                                .font(.footnote.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                    if let lanURL = connection.lanURLString {
                        LabeledContent("局域网地址") {
                            Text(lanURL)
                                .font(.footnote.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("服务器")
                }

                Section("外观") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("主题", systemImage: "paintbrush.fill")
                        .font(.subheadline.weight(.medium))
                    Picker("主题", selection: $theme.mode) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("跟随系统，或手动固定为深色/浅色")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

                Section("播放") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("播放器内核", systemImage: "play.rectangle.fill")
                            .font(.subheadline.weight(.medium))
                        Picker("播放器内核", selection: $playerSettings.engine) {
                            ForEach(PlayerEngine.allCases) { engine in
                                Text(engine.title).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(playerSettings.engine.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    if playerSettings.engine == .mpv {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("解码方式", systemImage: "cpu")
                                .font(.subheadline.weight(.medium))
                            Picker("解码方式", selection: $playerSettings.decodeMode) {
                                ForEach(DecodeMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(playerSettings.decodeMode.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("缓存") {
                    NavigationLink {
                        MusicCacheView()
                    } label: {
                        Label("歌曲缓存", systemImage: "arrow.down.circle.fill")
                    }
                    LabeledContent("已用空间", value: cacheService.formattedTotal())
                    Picker("最大缓存", selection: $cacheSettings.maxBytes) {
                        ForEach(MusicCacheSizeOption.allCases) { option in
                            Text(option.title).tag(option.bytes)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("隐私") {
                    Toggle(isOn: $privacy.isEnabled) {
                        Label {
                            Text("隐私模式")
                        } icon: {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.tint)
                        }
                    }

                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("隐私设置", systemImage: "gearshape.fill")
                    }
                }

                Section("支持") {
                    NavigationLink {
                        SupportDeveloperView()
                    } label: {
                        Label("支持开发者", systemImage: "heart.fill")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await service.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .task { cacheService.refresh() }
            .onChange(of: cacheSettings.maxBytes) { _, _ in cacheService.enforceLimit() }
        }
    }
}
