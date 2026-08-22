import SwiftUI

struct MusicPlaylistView: View {
    let playlist: MusicPlaylist
    @State private var detail: MusicPlaylistDetail?
    @State private var isLoading = true
    private let service = MusicService.shared
    private let audio = MusicAudioPlayer.shared
    var body: some View {
        Group {
            if isLoading {
                AppLoadingView(title: "加载歌单…")
            } else if let detail, let songs = detail.songs {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.name).font(.title3.bold())
                            if let c = detail.comment, !c.isEmpty { Text(c).foregroundStyle(.secondary).font(.subheadline) }
                            HStack(spacing: 12) {
                                Label(detail.isPublic == true ? "公开" : "私有", systemImage: detail.isPublic == true ? "globe" : "lock").font(.caption)
                                Text("\(songs.count) 首").font(.caption).foregroundStyle(.secondary)
                                if let d = detail.createdAt { Text(String(d.prefix(10))).font(.caption2).foregroundStyle(.tertiary) }
                            }
                            if detail.isPublic == true {
                                Label("公开歌单对所有登录用户可见，他人可查看并播放", systemImage: "eye")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            HStack(spacing: 12) {
                                Button {
                                    guard let first = songs.first else { return }
                                    audio.play(first, queue: songs)
                                } label: {
                                    Label("播放全部", systemImage: "play.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
                                }.buttonStyle(.plain).disabled(songs.isEmpty)
                                Menu {
                                    Button(role: .destructive) {
                                        Task {
                                            try? await service.deletePlaylist(id: playlist.id)
                                            GlobalNotice.shared.show("已删除歌单")
                                        }
                                    } label: { Label("删除歌单", systemImage: "trash") }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 40, height: 40).background(Color.appSurface, in: Circle())
                                }
                            }.padding(.top, 4)
                        }.padding(.vertical, 6)
                    }
                    Section("曲目") {
                        ForEach(songs.indices, id: \.self) { idx in
                            let song = songs[idx]
                            PlaylistSongRow(idx: idx, song: song, songs: songs, playlist: detail)
                        }
                    }
                }
                .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Color.appBackground)
            } else {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text("歌单不存在或无权限"))
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(playlist.name).navigationBarTitleDisplayMode(.inline)
        .task { isLoading = true; defer { isLoading = false }; detail = try? await service.fetchPlaylistDetail(id: playlist.id) }
        .refreshable { detail = try? await service.fetchPlaylistDetail(id: playlist.id) }
    }
}
