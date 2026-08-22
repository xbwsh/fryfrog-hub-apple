import SwiftUI

/// 分库网格海报样式（按库持久化，key = "libraryPosterMode-<libraryId>"）
private enum PosterMode: String {
    case portrait
    case landscape
}

/// 媒体库详情页（分库总览：系列卡片网格，支持横屏/竖屏海报切换并记忆）
struct LibraryDetailView: View {
    let group: LibrarySeriesGroup

    @State private var posterMode: PosterMode

    init(group: LibrarySeriesGroup) {
        self.group = group
        let saved = UserDefaults.standard.string(forKey: Self.modeKey(for: group.id))
        _posterMode = State(initialValue: PosterMode(rawValue: saved ?? "") ?? .portrait)
    }

    private static func modeKey(for libraryId: Int64) -> String {
        "libraryPosterMode-\(libraryId)"
    }

    var body: some View {
        ScrollView {
            if posterMode == .portrait {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                    spacing: 16
                ) {
                    ForEach(group.allItems) { item in
                        NavigationLink {
                            SeriesDetailView(series: item, onFavoriteChanged: nil)
                        } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                    spacing: 16
                ) {
                    ForEach(group.allItems) { item in
                        NavigationLink {
                            SeriesDetailView(series: item, onFavoriteChanged: nil)
                        } label: {
                            LandscapePosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(Color.appBackground)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("海报样式", selection: $posterMode) {
                        Label("竖屏海报", systemImage: "rectangle.portrait").tag(PosterMode.portrait)
                        Label("横屏海报", systemImage: "rectangle").tag(PosterMode.landscape)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .onChange(of: posterMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey(for: group.id))
        }
    }
}

/// 横屏海报卡片（16:9 fanart 封面 + 标题）
private struct LandscapePosterCard: View {
    let item: SeriesListDTO

    private var privacy: PrivacySettings { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ServerImageView(path: item.fanartUrl ?? item.coverUrl)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .privacyProtected(privacy.isEnabled && item.isAdult == true)

            Text(item.displayTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
