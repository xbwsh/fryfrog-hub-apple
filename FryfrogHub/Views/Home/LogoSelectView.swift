import SwiftUI

/// 手动设置 Logo：从 TMDB logo-options 中选择一张应用
struct LogoSelectView: View {
    enum Mode {
        case movie(videoId: Int64)
        case series(seriesId: Int64)
    }

    let mode: Mode
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var options: [LogoOption] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = VideoService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && options.isEmpty {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if options.isEmpty {
                    ContentUnavailableView(
                        "无可用 Logo",
                        systemImage: "character.book.closed",
                        description: Text("该条目暂无 TMDB Logo 选项")
                    )
                } else {
                    List(options) { option in
                        Button {
                            Task { await setLogo(option) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ServerImageView(path: option.url)
                                    .frame(height: 64)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 8))
                                    .clipped()
                                Text(option.displayLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("手动设置 Logo")
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
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        switch mode {
        case .movie(let videoId):
            options = await service.fetchMovieLogoOptions(id: videoId)
        case .series(let seriesId):
            options = await service.fetchSeriesLogoOptions(id: seriesId)
        }
    }

    private func setLogo(_ option: LogoOption) async {
        guard let filePath = option.filePath else { return }
        do {
            switch mode {
            case .movie(let videoId):
                try await service.setMovieLogo(id: videoId, filePath: filePath)
            case .series(let seriesId):
                try await service.setSeriesLogo(id: seriesId, filePath: filePath)
            }
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LogoSelectView(mode: .movie(videoId: 1)) {}
}
