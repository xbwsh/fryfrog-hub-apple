import SwiftUI

struct PlaylistSongRow: View {
    let idx: Int
    let song: MusicSong
    let songs: [MusicSong]
    let playlist: MusicPlaylistDetail?
    private let audio = MusicAudioPlayer.shared
    private let service = MusicService.shared
    var body: some View {
        HStack(spacing: 12) {
            Text("\(idx + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                Text(song.artistName ?? "未知歌手")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                audio.play(song, queue: songs)
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { audio.play(song, queue: songs) }
        .swipeActions {
            Button(role: .destructive) {
                guard let pid = playlist?.id else { return }
                Task {
                    try? await service.removeSongsFromPlaylist(id: pid, indexes: [idx])
                    GlobalNotice.shared.show("已移除")
                }
            } label: {
                Label("移除", systemImage: "trash")
            }
        }
    }
}
