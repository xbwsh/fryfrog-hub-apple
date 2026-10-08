import SwiftUI

struct PlaylistSongRow: View {
    let idx: Int
    let song: MusicSong
    let songs: [MusicSong]
    let playlist: MusicPlaylistDetail?
    /// 滑删回调（携带曲目下标）：由父视图执行删除+本地移除+重取，保证索引一致
    var onRemove: ((Int) -> Void)? = nil
    private let audio = MusicAudioPlayer.shared
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
                guard playlist?.id != nil else { return }
                onRemove?(idx)
            } label: {
                Label("移除", systemImage: "trash")
            }
        }
    }
}
