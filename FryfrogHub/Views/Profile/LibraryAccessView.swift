import SwiftUI

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
