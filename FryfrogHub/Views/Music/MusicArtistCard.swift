import SwiftUI

struct MusicArtistCard: View {
    let artist: MusicArtist

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ServerImageView(path: artist.coverUrl)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(artist.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(artist.albumCount) 张专辑")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
