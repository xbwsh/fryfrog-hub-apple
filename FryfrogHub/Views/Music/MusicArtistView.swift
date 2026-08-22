import SwiftUI

struct MusicArtistView: View {
    let artist: MusicArtist
    @State private var detail: MusicArtist?
    @State private var selectedAlbum: MusicAlbum?
    private let service = MusicService.shared

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        artistHeader(detail)
                        Text("专辑")
                            .font(.headline)
                            .padding(.horizontal)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 142), spacing: 16)],
                            spacing: 20
                        ) {
                            ForEach(detail.albums ?? []) { album in
                                MusicAlbumCard(album: album)
                                    .onTapGesture { selectedAlbum = album }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            } else {
                AppLoadingView(title: "加载歌手…")
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedAlbum) { album in
            MusicAlbumView(album: album)
        }
        .task {
            await service.loadArtist(id: artist.id)
            detail = service.selectedArtist
        }
    }

    private func artistHeader(_ artist: MusicArtist) -> some View {
        HStack(spacing: 16) {
            ServerImageView(path: artist.coverUrl)
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(artist.name).font(.title3.bold())
                Text("\(artist.albumCount) 张专辑")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }
}
