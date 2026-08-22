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

// MARK: - 支持开发者

/// 打赏渠道配置（替换为你的实际收款码 / 爱发电主页）
enum SupportConfig {
    /// 爱发电主页链接
    static let afdianURLString = "https://afdian.com"
    /// 微信收款码图片名（Assets.xcassets/WechatReward.imageset 内放入 WechatReward.png）
    static let wechatRewardImage = "WechatReward"
    /// 支付宝收款码图片名（Assets.xcassets/AlipayReward.imageset 内放入 AlipayReward.png）
    static let alipayRewardImage = "AlipayReward"
}

/// 支持作者页：扫码打赏（微信/支付宝）+ 爱发电跳转
struct SupportDeveloperView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fryfrog Hub 是你自己的媒体库客户端，如果你觉得好用，欢迎打赏支持独立开发者 ☕")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("扫码打赏") {
                NavigationLink {
                    RewardQRView(imageName: SupportConfig.wechatRewardImage, title: "微信")
                } label: {
                    Label("微信", systemImage: "circle.hexagongrid.fill")
                        .foregroundStyle(.green)
                }
                NavigationLink {
                    RewardQRView(imageName: SupportConfig.alipayRewardImage, title: "支付宝")
                } label: {
                    Label("支付宝", systemImage: "circle.circle")
                        .foregroundStyle(.blue)
                }
            }

            Section("爱发电") {
                Button {
                    openAfdian()
                } label: {
                    Label("在爱发电支持", systemImage: "bolt.heart.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("支持开发者")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openAfdian() {
        guard let url = URL(string: SupportConfig.afdianURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// 收款码页面：展示二维码图（未配置时显示占位提示）
struct RewardQRView: View {
    let imageName: String
    let title: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .frame(width: 280, height: 280)
                    .overlay {
                        Text("\(title)收款码待配置")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
            }

            Text("长按识别图中二维码即可打赏")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("如何替换收款码：")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("把二维码图片放入 WechatReward.imageset / AlipayReward.imageset")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
private struct UserRow: View {
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
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(user.enabled == false && !isSelf ? 0.55 : 1)
    }
}

private struct CapsuleTag: View {
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

// MARK: - 媒体库授权

/// 管理员给某用户分配可访问的媒体库（ADMIN only）
struct LibraryAccessView: View {
    let user: User
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var libraries: [MediaLibrary] = []
    @State private var selected = Set<Int64>()
    @State private var assigned = Set<Int64>()
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let auth = AuthService.shared
    private let libraryService = MediaLibraryService.shared

    private var isDirty: Bool { selected != assigned }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && libraries.isEmpty {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            if libraries.isEmpty {
                                Text("服务器上暂无媒体库")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(libraries) { library in
                                Button {
                                    toggle(library.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: library.typeIcon)
                                            .font(.body)
                                            .foregroundStyle(.white)
                                            .frame(width: 32, height: 32)
                                            .background(library.typeColor.gradient, in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(library.displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            if !library.subtitleText.isEmpty {
                                                Text(library.subtitleText)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(library.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(library.id) ? Color.accentColor : .secondary)
                                    }
                                }
                            }
                        } footer: {
                            if selected.isEmpty {
                                Text("未选择任何媒体库，保存后该用户将看不到任何内容")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("媒体库授权 · \(user.username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") {
                            Task { await save() }
                        }
                        .disabled(!isDirty)
                    }
                }
            }
            .task { await load() }
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

    private func toggle(_ id: Int64) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func load() async {
        guard libraries.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        await libraryService.fetchLibraries()
        libraries = libraryService.libraries
        if let ids = try? await auth.fetchUserLibraries(id: user.id) {
            assigned = Set(ids)
            selected = assigned
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await auth.assignLibraries(to: user.id, libraryIds: selected.sorted())
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
