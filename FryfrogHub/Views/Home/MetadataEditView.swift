import SwiftUI

/// 编辑元数据：电影 / 剧集两套字段，仅提交非空字段
struct MetadataEditView: View {
    enum Mode {
        case movie(VideoDTO)
        case series(SeriesDTO)
    }

    let mode: Mode
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var originalTitle = ""
    @State private var year = ""
    @State private var rating = ""
    @State private var releaseDate = ""
    @State private var genre = ""
    @State private var director = ""
    @State private var actors = ""
    @State private var status = ""
    @State private var overview = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let service = VideoService.shared

    init(mode: Mode, onSaved: @escaping () -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .movie(let video):
            _title = State(initialValue: video.title ?? "")
            _originalTitle = State(initialValue: video.originalTitle ?? "")
            _year = State(initialValue: video.year.map { String($0) } ?? "")
            _rating = State(initialValue: video.rating.map { String($0) } ?? "")
            _releaseDate = State(initialValue: video.releaseDate ?? "")
            _genre = State(initialValue: video.genre ?? "")
            _director = State(initialValue: video.director ?? "")
            _actors = State(initialValue: video.actors ?? "")
            _overview = State(initialValue: video.overview ?? "")
        case .series(let series):
            _title = State(initialValue: series.title ?? "")
            _originalTitle = State(initialValue: series.originalTitle ?? "")
            _year = State(initialValue: series.year.map { String($0) } ?? "")
            _rating = State(initialValue: series.rating.map { String($0) } ?? "")
            _releaseDate = State(initialValue: series.releaseDate ?? "")
            _status = State(initialValue: series.status ?? "")
            _overview = State(initialValue: series.overview ?? "")
        }
    }

    private var isSeries: Bool {
        if case .series = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    TextField("原始标题", text: $originalTitle)
                    TextField("年份", text: $year)
                        .keyboardType(.numberPad)
                    TextField("评分", text: $rating)
                        .keyboardType(.decimalPad)
                    TextField("上映日期（2023-01-22）", text: $releaseDate)
                }

                if isSeries {
                    Section("剧集") {
                        TextField("播出状态（Returning Series / Ended）", text: $status)
                    }
                } else {
                    Section("电影") {
                        TextField("类型（逗号分隔）", text: $genre)
                        TextField("导演", text: $director)
                        TextField("演员（逗号分隔）", text: $actors)
                    }
                }

                Section("简介") {
                    TextEditor(text: $overview)
                        .frame(minHeight: 100)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("编辑元数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                    }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .movie(let video):
                let request = VideoMetadataUpdateRequest(
                    title: emptyToNil(title),
                    overview: emptyToNil(overview),
                    rating: Double(rating),
                    year: Int(year),
                    releaseDate: emptyToNil(releaseDate),
                    genre: emptyToNil(genre),
                    director: emptyToNil(director),
                    actors: emptyToNil(actors),
                    originalTitle: emptyToNil(originalTitle),
                    tags: nil
                )
                try await service.updateVideoMetadata(id: video.id, request: request)
            case .series(let series):
                let request = SeriesMetadataUpdateRequest(
                    title: emptyToNil(title),
                    overview: emptyToNil(overview),
                    rating: Double(rating),
                    year: Int(year),
                    releaseDate: emptyToNil(releaseDate),
                    originalTitle: emptyToNil(originalTitle),
                    status: emptyToNil(status)
                )
                try await service.updateSeriesMetadata(id: series.id, request: request)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func emptyToNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    MetadataEditView(mode: .series(.init(
        id: 1, type: "series", title: "示例", coverUrl: nil, fanartUrl: nil,
        originalTitle: nil, overview: "简介", logoUrl: nil, mediaType: "tv",
        tmdbId: nil, rating: 8.0, year: 2020, releaseDate: "2020-01-01",
        seasonNumber: nil, numberOfSeasons: nil, totalEpisodes: nil, status: "Ended",
        isAdult: false, favorite: false, episodeCount: nil, seasons: nil, resolutions: nil
    ))) {}
}
