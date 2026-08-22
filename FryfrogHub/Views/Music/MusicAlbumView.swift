import SwiftUI

struct MusicAlbumView: View {
    let album: MusicAlbum
    @State private var detail: MusicAlbum?
    private let service = MusicService.shared
    private let audioPlayer = MusicAudioPlayer.shared
    @State private var cacheService = MusicCacheService.shared

    var body: some View {
        Group {
            if let detail, let songs = detail.songs {
                List {
                    Section {
                        albumHeader(detail)
                    }
                    Section("曲目") {
                        ForEach(songs) { song in
                            HStack(spacing: 12) {
                                Text(song.trackNumber.map(String.init) ?? "•")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(song.title).foregroundStyle(.primary).lineLimit(1)
                                    Text(song.artistName ?? "未知歌手")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(song.durationText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                if cacheService.isCached(song) {
                                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { audioPlayer.play(song, queue: songs) }
                            .swipeActions(edge: .trailing) {
                                if cacheService.isCached(song) {
                                    Button(role: .destructive) { cacheService.remove(song: song) } label: { Label("移除缓存", systemImage: "trash") }
                                } else {
                                    Button { Task { try? await cacheService.download(song: song) } } label: { Label("缓存", systemImage: "arrow.down.circle") }.tint(.green)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.appBackground)
            } else {
                AppLoadingView(title: "加载专辑…")
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await service.loadAlbum(id: album.id)
            detail = service.selectedAlbum
        }
    }

    private func albumHeader(_ album: MusicAlbum) -> some View {
        HStack(spacing: 16) {
            ServerImageView(path: album.coverUrl)
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(album.title).font(.headline)
                Text(album.artistName ?? "未知歌手").foregroundStyle(.secondary)
                if let year = album.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 8)
    }
}
