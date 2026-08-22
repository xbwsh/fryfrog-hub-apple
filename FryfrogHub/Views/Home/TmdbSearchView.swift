import SwiftUI

/// TMDB 搜索并绑定：videoId 传视频 ID（系列传入其任意一集 ID 即可绑定整个同标题系列）
struct TmdbSearchView: View {
    let videoId: Int64
    var onBound: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [TmdbSearchItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let service = VideoService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索电影 / 电视剧", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                if isSearching {
                    Spacer()
                    ProgressView("搜索中…")
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "搜索 TMDB",
                        systemImage: "magnifyingglass",
                        description: Text("输入关键词搜索，点击结果即可绑定\n绑定后会自动重命名文件")
                    )
                    Spacer()
                } else {
                    List(results) { item in
                        Button {
                            Task { await bind(item) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayTitle)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !item.detailText.isEmpty {
                                        Text(item.detailText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(item.bindMediaType == "tv" ? "剧集" : "电影")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("搜索并绑定 TMDB")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await service.searchTmdb(trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bind(_ item: TmdbSearchItem) async {
        do {
            try await service.bindTmdb(videoId: videoId, tmdbId: item.id, mediaType: item.bindMediaType)
            onBound()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TmdbSearchView(videoId: 1) {}
}
