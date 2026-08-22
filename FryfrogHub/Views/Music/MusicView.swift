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
                }
            }
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

private struct MusicSongRow: View {
    let song: MusicSong
    let queue: [MusicSong]
    private let audioPlayer = MusicAudioPlayer.shared
    @State private var cacheService = MusicCacheService.shared
    @State private var isDownloading = false
    @State private var showAddToPlaylist = false

    var body: some View {
        HStack(spacing: 12) {
            ServerImageView(path: song.coverUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(song.artistName ?? "未知歌手")
                    if let album = song.albumName, !album.isEmpty {
                        Text("· \(album)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(song.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if song.trackNumber != nil {
                    Text("#\(song.trackNumber!)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            // 收藏
            Button {
                Task {
                    do {
                        try await MusicService.shared.setStar(type: "songs", id: song.id, starred: !song.starred)
                        GlobalNotice.shared.show(!song.starred ? "已收藏" : "已取消收藏")
                    } catch { GlobalNotice.shared.show("收藏失败：\(error.localizedDescription)") }
                }
            } label: {
                Image(systemName: song.starred ? "heart.fill" : "heart")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(song.starred ? Color.red : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            Group {
                if cacheService.isCached(song) {
                    Button { cacheService.remove(song: song) } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                } else if isDownloading {
                    ProgressView().frame(width: 28, height: 28)
                } else {
                    Button {
                        Task {
                            isDownloading = true
                            try? await cacheService.download(song: song)
                            isDownloading = false
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { audioPlayer.play(song, queue: queue) } label: {
                Image(systemName: audioPlayer.currentSong?.id == song.id && audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { audioPlayer.play(song, queue: queue) }
        .contextMenu {
            Button {
                Task {
                    do { try await MusicService.shared.setStar(type: "songs", id: song.id, starred: !song.starred) } catch {}
                }
            } label: { Label(song.starred ? "取消收藏" : "收藏", systemImage: song.starred ? "heart.slash" : "heart") }
            Button { showAddToPlaylist = true } label: { Label("加入歌单", systemImage: "music.note.list") }
            if cacheService.isCached(song) {
                Button(role: .destructive) { cacheService.remove(song: song) } label: { Label("移除缓存", systemImage: "trash") }
            } else {
                Button { Task { try? await cacheService.download(song: song) } } label: { Label("缓存歌曲", systemImage: "arrow.down.circle") }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) { AddToPlaylistSheet(songId: song.id) }
    }
}

private struct MusicAlbumCard: View {
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

private struct MusicArtistCard: View {
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

// MARK: - 歌单

private struct MusicPlaylistRow: View {
    let playlist: MusicPlaylist
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "music.note.list").foregroundStyle(Color.accentColor).font(.title3)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        if let c = playlist.comment, !c.isEmpty {
                            Text(c).lineLimit(1)
                            Text("·").foregroundStyle(.tertiary)
                        }
                        if playlist.isPublic == true {
                            HStack(spacing: 4) {
                                Label("公开", systemImage: "globe")
                                if playlist.userId != AuthService.shared.currentUser?.id {
                                    Text("他人").foregroundStyle(.orange)
                                }
                            }
                            .font(.caption2)
                        } else {
                            Label("私有", systemImage: "lock").font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary).font(.caption).lineLimit(1)
                    if playlist.isPublic == true, playlist.userId != AuthService.shared.currentUser?.id, let uid = playlist.userId {
                        Text("创建者 ID: \(uid)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

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

private struct PlaylistSongRow: View {
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

private struct CreatePlaylistSheet: View {
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var comment = ""
    @State private var isPublic = false
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    TextField("备注（可选）", text: $comment)
                    Toggle("公开", isOn: $isPublic)
                } header: {
                    Text("歌单信息")
                } footer: {
                    if isPublic {
                        Label("公开后，所有登录用户可在“歌单”列表看到该歌单，可查看并播放其中的歌曲（无法修改）。他人将能看到歌单名称、备注及创建者昵称，请勿包含隐私内容。", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("私有歌单仅自己可见，他人无法查看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("新建歌单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            do {
                                _ = try await MusicService.shared.createPlaylist(name: name, comment: comment.isEmpty ? nil : comment, isPublic: isPublic, songIds: [])
                                GlobalNotice.shared.show("已创建“\(name)”")
                                await onCreated()
                                dismiss()
                            } catch { GlobalNotice.shared.show("创建失败：\(error.localizedDescription)") }
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}

private struct AddToPlaylistSheet: View {
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

private struct MusicMiniPlayer: View {
    let onTap: () -> Void
    @State private var audioPlayer = MusicAudioPlayer.shared
    private let cornerRadius: CGFloat = 18

    var body: some View {
        let duration = audioPlayer.currentSong?.durationSeconds ?? 0
        let progress = duration > 0 ? min(max(audioPlayer.position / duration, 0), 1) : 0
        let song = audioPlayer.currentSong

        ZStack(alignment: .bottom) {
            HStack(spacing: 14) {
                // 左侧：封面 + 信息（点击展开全屏）
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 52, height: 52)
                            ServerImageView(path: song?.coverUrl)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                                )
                                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                                .id(song?.id ?? 0) // 关键：切歌时强制刷新封面，避免旧图残留
                        }
                        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: song?.id)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(song?.title ?? "正在播放")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(song?.artistName ?? "未知歌手")
                                    .foregroundStyle(.secondary)
                                if let album = song?.albumName, !album.isEmpty {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(album).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 右侧控件：上一首 + 播放/暂停 + 下一首（修复缺失上一首）
                HStack(spacing: 8) {
                    Button {
                        audioPlayer.playPrevious()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.08), in: Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .opacity(song == nil ? 0.35 : 1)
                    .disabled(song == nil)

                    Button {
                        audioPlayer.toggle()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: Color.accentColor.opacity(0.32), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(audioPlayer.isPlaying ? "暂停" : "播放")

                    Button {
                        audioPlayer.playNext()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.08), in: Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .opacity(song == nil ? 0.35 : 1)
                    .disabled(song == nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, 6)

            // 底部进度条：3pt 胶囊，带平滑动画
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.primary.opacity(0.88))
                        .frame(width: proxy.size.width * progress, height: 3)
                        .animation(.linear(duration: 0.5), value: progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 14)
            .padding(.bottom, 7)
            .opacity(duration > 0 ? 1 : 0)
        }
        .background { glassBackground }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: 600)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: song?.id)
    }

    @ViewBuilder
    private var glassBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}

private struct MusicNowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var audioPlayer = MusicAudioPlayer.shared
    @State private var lyrics: String?
    @State private var parsedLyrics: [LyricsLine]?
    @State private var showLyrics = false
    @State private var isSeeking = false
    @State private var sliderValue: Double = 0
    @State private var showAddToPlaylist = false

    private let musicService = MusicService.shared

    private var duration: Double { audioPlayer.currentSong?.durationSeconds ?? 0 }
    private var hasDuration: Bool { duration > 1 }

    private var currentLyricIndex: Int? {
        guard let parsedLyrics, !parsedLyrics.isEmpty else { return nil }
        let position = isSeeking ? sliderValue : audioPlayer.position
        var current: Int?
        for line in parsedLyrics where line.time <= position { current = line.id }
        return current
    }

    var body: some View {
        ZStack {
            // 沉浸式背景：封面模糊 + 渐变遮罩
            nowPlayingBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部栏：收起 + 标题 + 更多
                topBar

                // 模式切换：歌曲 / 歌词（胶囊分段）
                modeSwitcher
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                if showLyrics {
                    lyricsContainer
                        .padding(.top, 6)
                } else {
                    playerContainer
                }
            }
        }
        .tint(.primary)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showLyrics)
        .task(id: audioPlayer.currentSong?.id) {
            lyrics = nil
            parsedLyrics = nil
            if let song = audioPlayer.currentSong {
                let content = await musicService.fetchLyrics(for: song)
                lyrics = content
                if let content { parsedLyrics = Self.parseLrc(content) }
            }
        }
        .onAppear { sliderValue = audioPlayer.position }
        .onChange(of: audioPlayer.position) { _, newValue in
            if !isSeeking { sliderValue = newValue }
        }
    }

    // MARK: - 背景

    private var nowPlayingBackground: some View {
        ZStack {
            Color.appBackground
            if let cover = audioPlayer.currentSong?.coverUrl {
                ServerImageView(path: cover)
                    .scaledToFill()
                    .blur(radius: 42)
                    .opacity(0.55)
                    .overlay {
                        LinearGradient(
                            colors: [Color.black.opacity(0.05), Color.black.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
            } else {
                LinearGradient(
                    colors: [Color.appSurface, Color.appBackground],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // 顶部高光 + 底部加深，突出封面卡片
            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .top, startRadius: 20, endRadius: 520
            )
            .opacity(0.6)
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack(alignment: .center) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(audioPlayer.currentSong?.albumName ?? "播放队列")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                if let song = audioPlayer.currentSong {
                    Label(song.artistName ?? "未知歌手", systemImage: "person")
                    Label(song.albumName ?? "未知专辑", systemImage: "opticaldisc")
                    Divider()
                    Button { Task { try? await MusicCacheService.shared.download(song: song) } } label: {
                        Label("缓存到本地", systemImage: "arrow.down.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            modeButton(title: "歌曲", icon: "music.note", selected: !showLyrics) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showLyrics = false }
            }
            modeButton(title: "歌词", icon: "text.quote", selected: showLyrics) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showLyrics = true }
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.22), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .frame(maxWidth: 220)
        .frame(maxWidth: .infinity)
    }

    private func modeButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.semibold))
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.primary : Color.white.opacity(0.62))
            .background {
                if selected {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 播放主体

    private var playerContainer: some View {
        GeometryReader { geo in
            let isCompactHeight = geo.size.height < 640
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // 分区 1：封面
                    artworkCard(isCompact: isCompactHeight)

                    // 分区 2：信息（标题+歌手），与封面拉开
                    songInfo
                        .padding(.top, isCompactHeight ? 20 : 26)

                    // 分区 3：进度（与信息用留白分隔，无背景/分割线）
                    progressSection
                        .padding(.top, isCompactHeight ? 20 : 24)
                        .padding(.horizontal, 24)

                    // 分区 4：控制（与进度留白分隔，无额外背景）
                    controlsSection
                        .padding(.top, isCompactHeight ? 24 : 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
    }

    private func artworkCard(isCompact: Bool) -> some View {
        let side: CGFloat = 340
        let cardSize: CGFloat = isCompact ? 260 : side
        return ZStack {
            // 阴影底座
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .frame(width: cardSize, height: cardSize)
                .blur(radius: 18)
                .offset(y: 14)
                .opacity(0.9)

            ServerImageView(path: audioPlayer.currentSong?.coverUrl)
                .frame(width: cardSize, height: cardSize)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                .scaleEffect(audioPlayer.isPlaying ? 1.0 : 0.97)
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: audioPlayer.isPlaying)
                // 封面四角信息：与右下角 waveform 同款 ultraThinMaterial 风格，置于封面左右侧
                .overlay(alignment: .topLeading) {
                    if let song = audioPlayer.currentSong, MusicCacheService.shared.isCached(song) {
                        Label("已缓存", systemImage: "arrow.down.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                            .padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let bitRate = audioPlayer.currentSong?.bitRate, bitRate > 0 {
                        Text("\(bitRate) kbps")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                            .padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // 播放状态微光（保留右下角统一样式）
                    if audioPlayer.isPlaying {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: "waveform").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.9)))
                            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                            .padding(12)
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var songInfo: some View {
        VStack(spacing: 5) {
            // 标题 + 年份：inline 胶囊，居中但保持紧凑
            HStack(alignment: .center, spacing: 8) {
                Text(audioPlayer.currentSong?.title ?? "未在播放")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .truncationMode(.tail)

                if let year = audioPlayer.currentSong?.year {
                    Text(String(year))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.70))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                        .fixedSize()
                }
            }
            .frame(maxWidth: 420)

            HStack(spacing: 5) {
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.32))
                Text(audioPlayer.currentSong?.artistName ?? "未知歌手")
                    .foregroundStyle(.white.opacity(0.84))
                if let album = audioPlayer.currentSong?.albumName, !album.isEmpty {
                    Text("·").foregroundStyle(.white.opacity(0.32))
                    Text(album).foregroundStyle(.white.opacity(0.56)).lineLimit(1)
                }
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)

            // 收藏 / 加入歌单 快捷操作
            HStack(spacing: 10) {
                Button {
                    guard let song = audioPlayer.currentSong else { return }
                    let newStar = !song.starred
                    Task {
                        do {
                            try await musicService.setStar(type: "songs", id: song.id, starred: newStar)
                            audioPlayer.updateCurrentStarred(newStar)
                            GlobalNotice.shared.show(newStar ? "已收藏" : "已取消收藏")
                        } catch { GlobalNotice.shared.show("收藏失败：\(error.localizedDescription)") }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(audioPlayer.currentSong?.starred == true ? "已收藏" : "收藏", systemImage: audioPlayer.currentSong?.starred == true ? "heart.fill" : "heart")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(audioPlayer.currentSong?.starred == true ? Color.red : Color.white.opacity(0.78))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(audioPlayer.currentSong?.starred == true ? 0.14 : 0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(audioPlayer.currentSong == nil)

                Button { showAddToPlaylist = true } label: {
                    Label("加入歌单", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(audioPlayer.currentSong == nil)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: 420)
        .sheet(isPresented: $showAddToPlaylist) {
            if let song = audioPlayer.currentSong {
                AddToPlaylistSheet(songId: song.id)
            }
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            // 定制进度条：轨道 + 小圆点拇指，替代系统 Slider
            GeometryReader { geo in
                let total = max(duration, 1)
                let position = isSeeking ? sliderValue : audioPlayer.position
                let progress = total > 0 ? min(max(position / total, 0), 1) : 0
                let dotSize: CGFloat = isSeeking ? 14 : 10
                ZStack(alignment: .leading) {
                    // 背景轨道
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4)
                    // 已播轨道
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * progress, height: 4)
                    // 小圆点拇指
                    Circle()
                        .fill(Color.white)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: .black.opacity(0.24), radius: 4, y: 1)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .offset(x: max(0, geo.size.width * progress - dotSize / 2))
                        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSeeking)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !hasDuration { return }
                            if !isSeeking { isSeeking = true }
                            let x = min(max(value.location.x, 0), geo.size.width)
                            let pct = geo.size.width > 0 ? x / geo.size.width : 0
                            sliderValue = Double(pct) * total
                        }
                        .onEnded { _ in
                            if hasDuration { audioPlayer.seek(to: sliderValue) }
                            // 延迟重置 isSeeking，避免与 position 回写冲突
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isSeeking = false }
                        }
                )
                .onTapGesture { }
            }
            .frame(height: 12)
            .disabled(!hasDuration)
            .opacity(hasDuration ? 1 : 0.45)

            HStack {
                Text(formatTime(isSeeking ? sliderValue : audioPlayer.position))
                    .contentTransition(.numericText())
                Spacer()
                Text(hasDuration ? "-\(formatTime(max(0, duration - (isSeeking ? sliderValue : audioPlayer.position))))" : "--:--")
                    .foregroundStyle(.white.opacity(0.62))
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: 420)
    }

    private var controlsSection: some View {
        VStack(spacing: 14) {
            // 播放模式独立居中置于控制区上方，彻底避免挤占/右移，且保证可见
            Button {
                audioPlayer.cyclePlayMode()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                GlobalNotice.shared.show(audioPlayer.playMode.title)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: audioPlayer.playMode.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                    Text(audioPlayer.playMode.title)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.5)
                }
                .foregroundStyle(audioPlayer.playMode == .order ? Color.white : Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(audioPlayer.playMode == .order ? 0.10 : 0.16), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(audioPlayer.playMode == .order ? 0.10 : 0.20), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放模式：\(audioPlayer.playMode.title)")

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                Button {
                    audioPlayer.playPrevious()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer().frame(width: 28)

                Button {
                    audioPlayer.toggle()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)
                            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.black)
                            .offset(x: audioPlayer.isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(audioPlayer.isPlaying ? 1.0 : 1.02)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: audioPlayer.isPlaying)

                Spacer().frame(width: 28)

                Button {
                    audioPlayer.playNext()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(.top, 4)
    }

    private var bottomActions: some View {
        HStack(spacing: 18) {
            // 缓存状态
            if let song = audioPlayer.currentSong {
                let isCached = MusicCacheService.shared.isCached(song)
                Label(isCached ? "已缓存" : "未缓存", systemImage: isCached ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isCached ? Color.green : Color.white.opacity(0.68))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }

            Spacer()

            // 音质 / 播放队列提示
            if let bitRate = audioPlayer.currentSong?.bitRate {
                Text("\(bitRate) kbps")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showLyrics = true }
            } label: {
                Image(systemName: "text.quote")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 420)
        .padding(.top, 6)
    }

    // MARK: - 歌词容器

    private var lyricsContainer: some View {
        VStack(spacing: 0) {
            // 顶部迷你信息 — 改为全宽透明，仅作信息展示，不再用独立卡片背景
            // 避免与下方歌词卡片形成上下双重断层
            HStack(spacing: 12) {
                ServerImageView(path: audioPlayer.currentSong?.coverUrl)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(audioPlayer.currentSong?.title ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(audioPlayer.currentSong?.artistName ?? "未知歌手")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                Text("\(formatTime(audioPlayer.position)) / \(formatTime(duration))")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            lyricsView
        }
    }

    private var lyricsView: some View {
        Group {
            if let parsedLyrics, !parsedLyrics.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .center, spacing: 18) {
                            Color.clear.frame(height: 28)
                            ForEach(parsedLyrics) { line in
                                let isCurrent = line.id == currentLyricIndex
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(isCurrent ? .system(size: 22, weight: .bold, design: .rounded) : .system(size: 17, weight: .medium, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.38))
                                    .shadow(color: isCurrent ? Color.black.opacity(0.30) : .clear, radius: 10, y: 4)
                                    .scaleEffect(isCurrent ? 1.04 : 1.0)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 2)
                                    .id(line.id)
                                    .animation(.spring(response: 0.36, dampingFraction: 0.82), value: currentLyricIndex)
                                    .onTapGesture {
                                        audioPlayer.seek(to: line.time)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                            }
                            Color.clear.frame(height: 80)
                        }
                        .padding(.vertical, 12)
                    }
                    .mask {
                        // 上下边缘羽化，消除卡片圆角带来的硬断层，改为沉浸式渐隐
                        LinearGradient(
                            colors: [Color.clear, Color.black, Color.black, Color.clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .onChange(of: currentLyricIndex) { _, index in
                        guard let index else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                    .onAppear {
                        if let idx = currentLyricIndex {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
                // 移除独立卡片背景：之前 Color.black.opacity(0.18)+RoundedRectangle 形成明显的上下左右断层
                // 改为透明，直透底层模糊封面背景，保证上下连贯
            } else if let lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(lyrics)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .lineSpacing(6)
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                }
                .mask {
                    LinearGradient(colors: [Color.clear, Color.black, Color.black, Color.clear], startPoint: .top, endPoint: .bottom)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.white.opacity(0.28))
                    Text("暂无歌词")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.78))
                    Text("这首歌曲没有可用的内嵌歌词或 LRC 文件")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.44))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            }
        }
        .frame(maxWidth: 560, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 解析 LRC 时间戳歌词（[mm:ss.xx] 或 [mm:ss.xxx]），返回按时间排序的歌词行。
    private static func parseLrc(_ text: String) -> [LyricsLine]? {
        guard let pattern = try? NSRegularExpression(
            pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#) else { return nil }
        var lines: [LyricsLine] = []
        var id = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let matches = pattern.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
            guard let first = matches.first else { continue }
            let minutes = Int(ns.substring(with: first.range(at: 1))) ?? 0
            let seconds = Int(ns.substring(with: first.range(at: 2))) ?? 0
            var time = Double(minutes * 60 + seconds)
            if first.range(at: 3).location != NSNotFound {
                let fraction = ns.substring(with: first.range(at: 3))
                if let value = Double(fraction) {
                    time += value / pow(10, Double(fraction.count))
                }
            }
            let content = pattern.stringByReplacingMatches(
                in: rawLine,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "")
            let lineText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(LyricsLine(id: id, time: time, text: lineText))
            id += 1
        }
        return lines.isEmpty ? nil : lines
    }
}

/// 单行歌词（含时间戳，用于同步滚动高亮）
private struct LyricsLine: Identifiable {
    let id: Int
    let time: Double
    let text: String
}
