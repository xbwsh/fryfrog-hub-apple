import SwiftUI

private enum MusicBrowseMode: String, CaseIterable, Hashable {
    case songs
    case albums
    case artists
    case playlists

    var title: String {
        switch self {
        case .songs: return "歌曲"
        case .albums: return "专辑"
        case .artists: return "歌手"
        case .playlists: return "歌单"
        }
    }

    var systemImage: String {
        switch self {
        case .songs: return "music.note.list"
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .playlists: return "list.star"
        }
    }
}

struct MusicView: View {
    @State private var service = MusicService.shared
    @State private var auth = AuthService.shared
    @State private var selectedAlbum: MusicAlbum?
    @State private var selectedArtist: MusicArtist?
    @State private var selectedPlaylist: MusicPlaylist?
    @State private var showPlayer = false
    @State private var isScanning = false
    @State private var browseMode: MusicBrowseMode = .songs
    @State private var searchText = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @Namespace private var capsuleNamespace
    @State private var playlists: [MusicPlaylist] = []
    @State private var isLoadingPlaylists = false

    private let audioPlayer = MusicAudioPlayer.shared
    private var isAdmin: Bool { auth.currentUser?.isAdmin == true }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.groups.isEmpty {
                    AppLoadingView(title: "加载音乐…")
                } else if let error = service.errorMessage, service.groups.isEmpty {
                    ContentUnavailableView("音乐加载失败", systemImage: "music.note", description: Text(error))
                } else if service.groups.isEmpty {
                    ContentUnavailableView("暂无音乐", systemImage: "music.note.list", description: Text("请先在后端创建并扫描音乐资源库"))
                } else {
                    musicContent
                }
            }
            .navigationTitle("音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await service.reload() }
                        } label: {
                            Label("刷新", systemImage: "arrow.triangle.2.circlepath")
                        }
                        if isAdmin {
                            Button {
                                Task {
                                    isScanning = true
                                    defer { isScanning = false }
                                    do {
                                        try await service.scan()
                                        GlobalNotice.shared.show("音乐扫描已启动，请稍后点击刷新")
                                    } catch {
                                        GlobalNotice.shared.show("音乐扫描启动失败：\(error.localizedDescription)")
                                    }
                                }
                            } label: {
                                Label("扫描媒体库", systemImage: isScanning ? "hourglass" : "arrow.clockwise")
                            }
                        }
                        Section("播放") {
                            Label("后台播放已启用", systemImage: "headphones")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .refreshable {
                await service.reload()
                await service.reloadSongs()
            }
            .task {
                await service.loadHome()
                await service.loadSongs()
                await loadPlaylists()
            }
            .task(id: browseMode) {
                if browseMode == .playlists { await loadPlaylists() }
            }
            .navigationDestination(item: $selectedAlbum) { album in
                MusicAlbumView(album: album)
            }
            .navigationDestination(item: $selectedArtist) { artist in
                MusicArtistView(artist: artist)
            }
            .navigationDestination(item: $selectedPlaylist) { playlist in
                MusicPlaylistView(playlist: playlist)
            }
            .sheet(isPresented: $showPlayer) {
                MusicNowPlayingView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if audioPlayer.currentSong != nil {
                    MusicMiniPlayer { showPlayer = true }
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            )
                        )
                }
            }
            // 迷你播放器出现/消失动画
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: audioPlayer.currentSong?.id)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var musicContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch browseMode {
                case .songs: songList
                case .albums: albumGrid
                case .artists: artistGrid
                case .playlists: playlistList
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .top, spacing: 0) { headerRow }
        .animation(.easeInOut(duration: 0.2), value: browseMode)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isSearching)
        .onChange(of: isSearching) { _, searching in
            if searching { searchFocused = true } else { searchFocused = false }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            if isSearching {
                collapsedBrowseButton
                searchField
                    .frame(maxWidth: .infinity)
            } else {
                browseSwitcher
                    .frame(maxWidth: .infinity, alignment: .leading)
                collapsedSearchButton
                    .fixedSize()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background {
            if #available(iOS 26.0, *) {
                Rectangle().fill(.clear)
            } else {
                Rectangle().fill(Color.appBackground.opacity(0.85))
                    .background(.ultraThinMaterial)
            }
        }
        .contentShape(Rectangle())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索歌曲、专辑或歌手", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("取消") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isSearching = false
                    searchText = ""
                }
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                    .matchedGeometryEffect(id: "capsule", in: capsuleNamespace)
            } else {
                Capsule().fill(Color.appSurface)
                    .matchedGeometryEffect(id: "capsule", in: capsuleNamespace)
            }
        }
    }

    private var collapsedSearchButton: some View {
        Button {
            isSearching = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
                .background {
                    if #available(iOS 26.0, *) {
                        Circle().fill(.clear).glassEffect(.regular, in: .circle)
                    } else {
                        Circle().fill(Color.appSurface)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索")
    }

    private var collapsedBrowseButton: some View {
        Button {
            isSearching = false
        } label: {
            Image(systemName: browseMode.systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
                .background {
                    if #available(iOS 26.0, *) {
                        Circle().fill(.clear).glassEffect(.regular, in: .circle)
                    } else {
                        Circle().fill(Color.appSurface)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(browseMode.title)
    }

    private var browseSwitcher: some View {
        let albumCount = service.groups.reduce(0) { $0 + $1.albums.count }
        let artistCount = service.groups.reduce(0) { $0 + $1.artists.count }
        let songCount = service.songs.count
        return HStack(spacing: 4) {
            browseButton(mode: .songs, count: songCount, systemImage: MusicBrowseMode.songs.systemImage)
            browseButton(mode: .albums, count: albumCount, systemImage: MusicBrowseMode.albums.systemImage)
            browseButton(mode: .artists, count: artistCount, systemImage: MusicBrowseMode.artists.systemImage)
            browseButton(mode: .playlists, count: playlists.count, systemImage: MusicBrowseMode.playlists.systemImage)
        }
        .padding(3)
        .frame(height: 36)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                    .matchedGeometryEffect(id: "capsule", in: capsuleNamespace)
            } else {
                Capsule().fill(.regularMaterial)
                    .overlay { Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5) }
                    .matchedGeometryEffect(id: "capsule", in: capsuleNamespace)
            }
        }
    }

    private func browseButton(mode: MusicBrowseMode, count: Int, systemImage: String) -> some View {
        let isSelected = browseMode == mode
        return Button {
            browseMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .background {
                if isSelected {
                    Capsule().fill(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var albumGrid: some View {
        let albums = service.groups.flatMap(\.albums).filter { album in
            searchText.isEmpty
                || album.title.localizedCaseInsensitiveContains(searchText)
                || (album.artistName?.localizedCaseInsensitiveContains(searchText) == true)
        }
        return Group {
            if albums.isEmpty {
                musicEmptyState(title: "没有找到专辑", systemImage: "square.stack")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 10)],
                    spacing: 18
                ) {
                    ForEach(albums) { album in
                        MusicAlbumCard(album: album)
                            .onTapGesture { selectedAlbum = album }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var artistGrid: some View {
        let artists = service.groups.flatMap(\.artists).filter { artist in
            searchText.isEmpty || artist.name.localizedCaseInsensitiveContains(searchText)
        }
        return Group {
            if artists.isEmpty {
                musicEmptyState(title: "没有找到歌手", systemImage: "person.2")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 10)],
                    spacing: 18
                ) {
                    ForEach(artists) { artist in
                        MusicArtistCard(artist: artist)
                            .onTapGesture { selectedArtist = artist }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var playlistList: some View {
        let filtered = playlists.filter { pl in
            searchText.isEmpty || pl.name.localizedCaseInsensitiveContains(searchText) || (pl.comment?.localizedCaseInsensitiveContains(searchText) == true)
        }
        return Group {
            if isLoadingPlaylists && filtered.isEmpty {
                ProgressView("加载歌单…").frame(maxWidth: .infinity, minHeight: 120)
            } else if filtered.isEmpty {
                ContentUnavailableView("暂无歌单", systemImage: "list.star", description: Text(searchText.isEmpty ? "创建你的第一个歌单" : "换个关键词试试"))
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { pl in
                        MusicPlaylistRow(playlist: pl) { selectedPlaylist = pl }
                    }
                }
                .padding(.horizontal)
            }
            // 创建入口
            Button {
                showCreatePlaylist = true
            } label: {
                Label("新建歌单", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 4)
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistSheet { await loadPlaylists() }
            }
        }
        .task { await loadPlaylists() }
    }

    private func loadPlaylists() async {
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        do { playlists = try await service.fetchPlaylists() } catch { playlists = [] }
    }

    @State private var showCreatePlaylist = false

    private var songList: some View {
        let filtered = service.songs.filter { song in
            searchText.isEmpty
                || song.title.localizedCaseInsensitiveContains(searchText)
                || (song.artistName?.localizedCaseInsensitiveContains(searchText) == true)
                || (song.albumName?.localizedCaseInsensitiveContains(searchText) == true)
        }
        return Group {
            if service.isLoadingSongs && filtered.isEmpty {
                ProgressView("加载歌曲…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if filtered.isEmpty {
                musicEmptyState(title: "没有找到歌曲", systemImage: "music.note.list")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { song in
                        MusicSongRow(song: song, queue: filtered)
                        if song.id != filtered.last?.id {
                            Divider().padding(.leading, 60).opacity(0.5)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
            }
        }
        .task { await service.loadSongs() }
    }

    private func musicEmptyState(title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("换个关键词试试"))
            .frame(maxWidth: .infinity)
    }
}
