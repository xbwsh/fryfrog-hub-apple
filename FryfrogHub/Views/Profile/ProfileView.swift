import SwiftUI

struct ProfileView: View {
    @State private var service = AuthService.shared
    @State private var connection = ServerConnection.shared
    @Bindable private var privacy = PrivacySettings.shared
    @Bindable private var theme = ThemeSettings.shared
    @Bindable private var playerSettings = PlayerSettings.shared
    @State private var cacheService = MusicCacheService.shared
    @Bindable private var cacheSettings = MusicCacheSettings.shared

    /// 延迟分档配色：<100ms 良好，<300ms 一般，其余较差
    private func latencyColor(_ ms: Int) -> Color {
        switch ms {
        case ..<100: .green
        case ..<300: .orange
        default: .red
        }
    }

    /// 延迟胶囊：右对齐展示，未测出时显示灰色 "--"
    private func latencyPill(_ ms: Int?) -> some View {
        let color = ms.map(latencyColor) ?? .gray
        return Text(ms.map { "\($0) ms" } ?? "--")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    /// 公网/局域网地址行：图标 + 名称（使用中高亮）+ 地址 + 延迟胶囊
    @ViewBuilder
    private func addressRow(_ mode: ServerConnectionMode) -> some View {
        if let url = connection.urlString(for: mode) {
            let isActive = connection.effectiveMode == mode
            HStack(spacing: 10) {
                Image(systemName: mode == .lan ? "wifi" : "globe")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(minWidth: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mode.title)
                            .font(.subheadline.weight(.medium))
                        if isActive {
                            Text("使用中")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }
                    Text(url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                latencyPill(connection.latency(for: mode))
            }
            .padding(.vertical, 2)
        }
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
                    if connection.hasAnyAddress {
                        addressRow(.public)
                        addressRow(.lan)
                    } else {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 9, height: 9)
                            Text("未配置")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text("服务器")
                        Spacer()
                        if connection.hasAnyAddress {
                            Button {
                                Task {
                                    async let modeRefresh: Void = connection.refreshActiveMode()
                                    async let latencyRefresh: Void = connection.refreshLatencies()
                                    _ = await (modeRefresh, latencyRefresh)
                                }
                            } label: {
                                if connection.isProbing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.footnote.weight(.medium))
                                }
                            }
                            .buttonStyle(.borderless)
                            // 延迟为 3s 静默轮询，不挂 isMeasuringLatency，避免按钮转圈闪烁
                            .disabled(connection.isProbing)
                            .accessibilityLabel("重新检测连接")
                        }
                    }
                } footer: {
                    if connection.hasLAN {
                        Text("局域网优先，失败自动切公网")
                    }
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

                Section("缓存") {
                    NavigationLink {
                        MusicCacheView()
                    } label: {
                        Label("歌曲缓存", systemImage: "arrow.down.circle.fill")
                    }
                    LabeledContent("已用空间", value: cacheService.formattedTotal())
                    NavigationLink {
                        MusicCacheLimitView()
                    } label: {
                        LabeledContent("最大缓存", value: cacheSettings.formattedMax())
                    }
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
            // 停留在本页期间每 3s 轮询延迟；离开页面时 .task 自动取消，停止轮询
            .task {
                while !Task.isCancelled {
                    await connection.refreshLatencies()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .onChange(of: cacheSettings.maxBytes) { _, _ in cacheService.enforceLimit() }
        }
    }
}
