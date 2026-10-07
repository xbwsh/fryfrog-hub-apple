import SwiftUI

struct LibraryView: View {
    @State private var service = MediaLibraryService.shared
    /// 各资源库最新流水线进度（轮询更新，驱动行的进度条）
    @State private var progressByLibrary: [Int64: PipelineProgressDTO] = [:]
    /// 进度轮询任务：仅在有扫描运行时持续轮询，空闲即停（避免后台空转）
    @State private var progressPollTask: Task<Void, Never>?
    /// 新建/编辑目标（nil 时不展示表单）
    @State private var editingTarget: EditTarget?
    /// 待删除的资源库（弹确认框）
    @State private var libraryToDelete: MediaLibrary?
    @State private var actionErrorMessage: String?
    private var privacy: PrivacySettings { .shared }

    /// 仅 ADMIN 显示媒体库管理操作（创建/编辑/删除/启停/扫描等；后端同时 403 兜底）
    private var isAdmin: Bool { AuthService.shared.currentUser?.isAdmin == true }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.libraries.isEmpty {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.libraries.isEmpty {
                    ContentUnavailableView(
                        "暂无媒体库",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text(isAdmin ? (service.errorMessage ?? "点右上角 + 新建媒体库") : "没有被分配可访问的媒体库")
                    )
                } else {
                    List {
                        if hiddenLibraryCount > 0 {
                            Section {
                                Label("已隐藏 \(hiddenLibraryCount) 个媒体库", systemImage: "eye.slash")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(Array(visibleLibraries.enumerated()), id: \.element.id) { index, library in
                            LibraryRow(
                                library: library,
                                progress: progressByLibrary[library.id],
                                showActions: isAdmin,
                                canMoveUp: index > 0,
                                canMoveDown: index < visibleLibraries.count - 1,
                                onMoveUp: { Task { await move(library, up: true) } },
                                onMoveDown: { Task { await move(library, up: false) } },
                                onToggle: { Task { await toggle(library) } },
                                onScan: { Task { await scan(library) } },
                                onEdit: { editingTarget = EditTarget(library: library) },
                                onDelete: { libraryToDelete = library }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if isAdmin {
                                    Button(role: .destructive) {
                                        libraryToDelete = library
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        editingTarget = EditTarget(library: library)
                                    } label: {
                                        Label("编辑", systemImage: "square.and.pencil")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if isAdmin {
                                    Button {
                                        Task { await toggle(library) }
                                    } label: {
                                        Label(library.enabled == true ? "停用" : "启用", systemImage: "power")
                                    }
                                    .tint(.blue)
                                    Button {
                                        Task { await scan(library) }
                                    } label: {
                                        Label("扫描", systemImage: "arrow.clockwise")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await service.fetchLibraries()
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("媒体库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isAdmin {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                Task { await scanAll() }
                            } label: {
                                Label("扫描全部媒体库", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("更多操作")

                        Button {
                            editingTarget = EditTarget(library: nil)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("新建媒体库")
                    }
                }
            }
            .task {
                await service.fetchLibraries()
                // 扫描/进度属于管理能力，仅 ADMIN 轮询
                if isAdmin {
                    startProgressPolling()
                }
            }
            .sheet(item: $editingTarget) { target in
                LibraryEditView(library: target.library) {
                    Task { await service.fetchLibraries() }
                }
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { actionErrorMessage != nil },
                    set: { if !$0 { actionErrorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(actionErrorMessage ?? "")
            }
            .confirmationDialog(
                "删除媒体库「\(libraryToDelete?.displayName ?? "")」？",
                isPresented: Binding(
                    get: { libraryToDelete != nil },
                    set: { if !$0 { libraryToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let library = libraryToDelete {
                        Task { await delete(library) }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("库内媒体记录将一并删除，此操作不可撤销")
            }
        }
    }

    private var visibleLibraries: [MediaLibrary] {
        service.libraries.filter { !privacy.isEnabled || $0.isAdult != true }
    }

    private var hiddenLibraryCount: Int {
        service.libraries.count - visibleLibraries.count
    }

    // MARK: - 动作

    private func toggle(_ library: MediaLibrary) async {
        do {
            try await service.toggle(id: library.id)
            await service.fetchLibraries()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func scan(_ library: MediaLibrary) async {
        do {
            try await service.scan(id: library.id)
            progressByLibrary[library.id] = PipelineProgressDTO(
                libraryId: library.id, stage: "scan", running: true, percent: 0, currentItem: nil
            )
            startProgressPolling()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func scanAll() async {
        do {
            try await service.scanAll()
            startProgressPolling()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ library: MediaLibrary) async {
        do {
            try await service.delete(id: library.id)
            progressByLibrary.removeValue(forKey: library.id)
            await service.fetchLibraries()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    /// 上移/下移调整排序：交换后按头尾顺序归一化 sortOrder，只提交有变化的库
    private func move(_ library: MediaLibrary, up: Bool) async {
        var list = service.libraries
        guard let from = list.firstIndex(where: { $0.id == library.id }) else { return }
        let to = up ? from - 1 : from + 1
        guard list.indices.contains(to) else { return }
        list.swapAt(from, to)

        let changes = list.enumerated()
            .filter { $0.element.sortOrder != $0.offset }
            .map { (library: $0.element, order: $0.offset) }
        for change in changes {
            do {
                try await service.update(change.library.id, request: MediaLibraryRequest(sortOrder: change.order))
            } catch {
                actionErrorMessage = error.localizedDescription
                return
            }
        }
        await service.fetchLibraries()
    }

    /// 轮询各资源库流水线进度（自动随视图生命周期取消）
    private func progressPollLoop() async {
        while !Task.isCancelled {
            let running = await refreshProgress()
            guard running else { return }
            // 扫描通常秒级~分钟级，2s 间隔足够平滑且省电
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// 开始（或重启）进度轮询：先立即刷新一次，保证扫描按钮触发的状态立刻可见
    private func startProgressPolling() {
        progressPollTask?.cancel()
        progressPollTask = Task {
            await refreshProgress()
            await progressPollLoop()
        }
    }

    @discardableResult
    private func refreshProgress() async -> Bool {
        let ids = service.libraries.map(\.id)
        guard !ids.isEmpty else { return false }
        await withTaskGroup(of: (Int64, PipelineProgressDTO?).self) { group in
            for id in ids {
                group.addTask { (id, await service.pipelineProgress(id: id)) }
            }
            for await (id, progress) in group {
                await MainActor.run { progressByLibrary[id] = progress }
            }
        }
        return progressByLibrary.values.contains { $0.isRunning }
    }
}

/// 新建/编辑弹窗的驱动目标
private struct EditTarget: Identifiable {
    var library: MediaLibrary?
    var id: String { library.map { "edit-\($0.id)" } ?? "create" }
}

/// 媒体库行：图标 + 名称/路径 + 扫描进度 + 操作菜单
private struct LibraryRow: View {
    let library: MediaLibrary
    let progress: PipelineProgressDTO?
    var showActions: Bool
    var canMoveUp: Bool
    var canMoveDown: Bool
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onToggle: () -> Void
    var onScan: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: library.typeIcon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(library.typeColor.gradient, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(library.displayName)
                        .font(.headline)
                    if library.enabled == false {
                        Text("停用")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.2), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(library.subtitleText.isEmpty ? "\(library.displayPath) · 未分类" : library.subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let progress, progress.isRunning {
                    progressSection(progress)
                }
            }

            Spacer()

            if showActions {
                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("编辑", systemImage: "square.and.pencil")
                    }
                    Button {
                        onToggle()
                    } label: {
                        Label(library.enabled == true ? "停用" : "启用", systemImage: "power")
                    }
                    Divider()
                    Button {
                        onMoveUp()
                    } label: {
                        Label("上移", systemImage: "chevron.up")
                    }
                    .disabled(!canMoveUp)
                    Button {
                        onMoveDown()
                    } label: {
                        Label("下移", systemImage: "chevron.down")
                    }
                    .disabled(!canMoveDown)
                    Divider()
                    Button {
                        onScan()
                    } label: {
                        Label("立即扫描", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.09), in: Circle())
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 4)
        // 停用态整体淡化
        .opacity(library.enabled == false && !(progress?.isRunning == true) ? 0.55 : 1)
    }

    /// 扫描中的进度条 + 阶段/百分比/当前项
    @ViewBuilder
    private func progressSection(_ progress: PipelineProgressDTO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: progress.progress)
                .tint(.orange)
            HStack(spacing: 4) {
                Text(progress.stageTitle)
                Text("\(Int(progress.progress * 100))%")
                if let item = progress.currentItem, !item.isEmpty {
                    Text("· \(item)")
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

// MARK: - 新建/编辑媒体库

/// 新建（library == nil）或编辑媒体库
struct LibraryEditView: View {
    let library: MediaLibrary?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var path = ""
    @State private var type = "VIDEO"
    @State private var subType = "MIXED"
    @State private var enabled = true
    @State private var enableScraping = true
    @State private var isAdult = false
    @State private var note = ""
    @State private var showBrowser = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = MediaLibraryService.shared

    init(library: MediaLibrary?, onSaved: @escaping () -> Void) {
        self.library = library
        self.onSaved = onSaved
        _name = State(initialValue: library?.name ?? "")
        _path = State(initialValue: library?.path ?? "")
        _type = State(initialValue: library?.type ?? "VIDEO")
        _subType = State(initialValue: library?.subType?.uppercased() ?? "MIXED")
        _enabled = State(initialValue: library?.enabled ?? true)
        _enableScraping = State(initialValue: library?.enableScraping ?? true)
        _isAdult = State(initialValue: library?.isAdult ?? false)
        _note = State(initialValue: library?.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("媒体库名称", text: $name)
                    TextField("目录路径，如 /data/media/video", text: $path)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        showBrowser = true
                    } label: {
                        Label("从服务器目录选择", systemImage: "folder.badge.plus")
                    }
                    Picker("类型", selection: $type) {
                        Text("视频").tag("VIDEO")
                        Text("音乐").tag("MUSIC")
                        Text("有声书").tag("AUDIOBOOK")
                        Text("漫画").tag("COMIC")
                        Text("电子书").tag("EBOOK")
                    }
                    if type == "VIDEO" {
                        Picker("子类型", selection: $subType) {
                            Text("混合").tag("MIXED")
                            Text("电影").tag("MOVIE")
                            Text("剧集").tag("TV")
                        }
                    }
                }

                Section("选项") {
                    Toggle("启用", isOn: $enabled)
                    if type == "VIDEO" {
                        Toggle("扫描时自动刮削", isOn: $enableScraping)
                    }
                    Toggle("成人内容库", isOn: $isAdult)
                }

                Section("备注") {
                    TextEditor(text: $note)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(library == nil ? "新建媒体库" : "编辑媒体库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button(library == nil ? "创建" : "保存") {
                            Task { await save() }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
            .sheet(isPresented: $showBrowser) {
                DirectoryBrowserView(selectedPath: $path)
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let request = MediaLibraryRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            subType: type == "VIDEO" ? subType : nil,
            enabled: enabled,
            enableScraping: enableScraping,
            isAdult: isAdult,
            sortOrder: nil,
            description: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            if let library {
                try await service.update(library.id, request: request)
            } else {
                try await service.create(request)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 服务器目录浏览器

/// 浏览/选择服务器的媒体目录（基于 /media-libraries/browse）
struct DirectoryBrowserView: View {
    @Binding var selectedPath: String
    @Environment(\.dismiss) private var dismiss

    @State private var currentPath: String?
    @State private var items: [LibraryBrowseItem] = []
    @State private var isLoading = false

    private let service = MediaLibraryService.shared

    private var isRoot: Bool { currentPath == nil }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("加载目录…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            if !isRoot, let currentPath {
                                Button {
                                    selectedPath = currentPath
                                    dismiss()
                                } label: {
                                    Label("选择当前目录", systemImage: "checkmark.circle.fill")
                                        .fontWeight(.semibold)
                                }
                            }
                            if !isRoot, let parent = parentPath {
                                Button {
                                    Task { await go(parent) }
                                } label: {
                                    Label("上一级（\(parent)）", systemImage: "chevron.up")
                                }
                            }
                        } footer: {
                            if let currentPath {
                                Text("当前：\(currentPath)")
                            }
                        }

                        Section(isRoot ? "磁盘根目录" : "子目录") {
                            if items.isEmpty {
                                Text("没有子目录")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(items) { item in
                                Button {
                                    Task { await go(item.path) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.writable == true ? "folder.fill" : "folder")
                                            .foregroundStyle(item.writable == true ? .blue : .secondary)
                                        Text(item.name)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if item.writable == false {
                                            Text("只读")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        if !isRoot {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.appBackground)
            .navigationTitle(isRoot ? "选择目录" : displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if !isRoot {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("根目录") {
                            Task { await go(nil) }
                        }
                    }
                }
            }
            .task { await go(nil) }
        }
    }

    private var displayTitle: String {
        guard let currentPath else { return "选择目录" }
        return (currentPath as NSString).lastPathComponent
    }

    private var parentPath: String? {
        guard let currentPath else { return nil }
        let parent = (currentPath as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    private func go(_ path: String?) async {
        currentPath = path
        await load(path)
    }

    private func load(_ path: String?) async {
        isLoading = true
        defer { isLoading = false }
        let result = await service.browse(path: path)
        if Task.isCancelled { return }
        items = result
    }
}
