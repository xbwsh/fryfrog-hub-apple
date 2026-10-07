import SwiftUI

/// 有声书重新刮削：搜索 Bangumi 候选并绑定
struct AudiobookScrapeView: View {
    let bookId: Int64
    let initialQuery: String
    var onBound: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [AudiobookScrapeCandidate] = []
    @State private var isSearching = false
    @State private var bindingId: String?
    @State private var errorMessage: String?

    private let service = AudiobookService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索有声书", text: $query)
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
                        "搜索 Bangumi",
                        systemImage: "magnifyingglass",
                        description: Text("输入关键词搜索，点击结果即可绑定\n绑定后会更新书名、作者、简介与封面")
                    )
                    Spacer()
                } else {
                    List(results) { item in
                        Button {
                            Task { await bind(item) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title ?? "未知")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !detailText(item).isEmpty {
                                        Text(detailText(item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if bindingId == item.id {
                                    ProgressView()
                                } else {
                                    Text("绑定")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .disabled(bindingId != nil)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("重新刮削")
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                if query.isEmpty && !initialQuery.isEmpty {
                    query = initialQuery
                    await search()
                }
            }
        }
    }

    private func detailText(_ item: AudiobookScrapeCandidate) -> String {
        var parts: [String] = []
        if let author = item.author { parts.append(author) }
        if let narrator = item.narrator { parts.append("演播：\(narrator)") }
        if let year = item.year { parts.append(String(year)) }
        if let rating = item.rating { parts.append(String(format: "★ %.1f", rating)) }
        return parts.joined(separator: " · ")
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await service.searchScrape(trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bind(_ item: AudiobookScrapeCandidate) async {
        bindingId = item.id
        defer { bindingId = nil }
        do {
            try await service.bindScrape(
                id: bookId,
                source: item.source ?? "bangumi",
                sourceId: item.sourceId
            )
            onBound()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
