import SwiftUI

struct AddToPlaylistSheet: View {
    let songId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [MusicPlaylist] = []
    @State private var isLoading = true
    @State private var showCreate = false
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载歌单…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    ContentUnavailableView("暂无歌单", systemImage: "list.star", description: Text("先创建一个歌单"))
                } else {
                    List(playlists) { pl in
                        Button {
                            Task {
                                do {
                                    try await MusicService.shared.addSongsToPlaylist(id: pl.id, songIds: [songId])
                                    GlobalNotice.shared.show("已加入“\(pl.name)”")
                                    dismiss()
                                } catch { GlobalNotice.shared.show("加入失败：\(error.localizedDescription)") }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pl.name).foregroundStyle(.primary)
                                    if let c = pl.comment, !c.isEmpty { Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("加入歌单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { showCreate = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showCreate) {
                CreatePlaylistSheet { playlists = (try? await MusicService.shared.fetchPlaylists()) ?? [] }
            }
            .task { isLoading = true; defer { isLoading = false }; playlists = (try? await MusicService.shared.fetchPlaylists()) ?? [] }
        }
    }
}
