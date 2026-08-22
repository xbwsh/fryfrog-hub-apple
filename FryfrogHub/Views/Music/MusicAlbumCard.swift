import SwiftUI

struct MusicAlbumCard: View {
    let album: MusicAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ServerImageView(path: album.coverUrl)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(album.artistName ?? "未知歌手")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
