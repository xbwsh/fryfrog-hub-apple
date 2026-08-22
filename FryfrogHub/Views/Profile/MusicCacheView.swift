import SwiftUI

struct MusicCacheView: View {
    @State private var cacheService = MusicCacheService.shared
    @Bindable private var settings = MusicCacheSettings.shared
    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            List {
            Section {
                Picker("最大缓存", selection: $settings.maxBytes) {
                    ForEach(MusicCacheSizeOption.allCases) { option in
                        Text(option.title).tag(option.bytes)
                    }
                }
                .pickerStyle(.navigationLink)
                Text("达到上限后会自动清理最旧的缓存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("容量设置")
            }

            Section {
                Toggle("播放时自动缓存", isOn: $settings.autoCacheOnPlay)
            } footer: {
                Text("开启后，播放歌曲时自动在后台下载并缓存，受容量上限控制。")
            }

            Section {
                LabeledContent("已用空间", value: cacheService.formattedTotal())
                LabeledContent("上限", value: settings.formattedMax())
                if settings.maxBytes != Int64.max {
                    let progress = min(Double(cacheService.totalBytes) / Double(settings.maxBytes), 1)
                    ProgressView(value: progress)
                        .tint(progress > 0.9 ? .red : .accentColor)
                }
                LabeledContent("已缓存", value: "\(cacheService.cachedSongs.count) 首")
            } header: {
                Text("使用情况")
            }

            Section {
                NavigationLink {
                    CachedSongsListView()
                } label: {
                    HStack {
                        Label("已缓存歌曲", systemImage: "music.note.list")
                        Spacer()
                        Text("\(cacheService.cachedSongs.count) 首")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(cacheService.cachedSongs.isEmpty)
                if cacheService.cachedSongs.isEmpty {
                    Text("暂无缓存")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("已缓存歌曲")
            }

            Section {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空全部缓存", systemImage: "trash.fill")
                }
                .disabled(cacheService.cachedSongs.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        }
        .navigationTitle("歌曲缓存")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { cacheService.refresh() }
        .confirmationDialog("清空全部缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { cacheService.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有已缓存的歌曲文件")
        }
    }
}

struct CachedSongsListView: View {
    @State private var cacheService = MusicCacheService.shared
    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Group {
                if cacheService.cachedSongs.isEmpty {
                    ContentUnavailableView("暂无缓存", systemImage: "music.note.list", description: Text("缓存的歌曲会显示在这里"))
                } else {
                    List {
                        ForEach(cacheService.cachedSongs) { info in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        if let artist = info.artistName, !artist.isEmpty {
                                            Text(artist).lineLimit(1)
                                            Text("·")
                                        }
                                        Text(ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
                                        Text("· \(info.modifiedDate.formatted(date: .abbreviated, time: .shortened))")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    cacheService.remove(info: info)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Section {
                            Button(role: .destructive) { showClearConfirm = true } label: {
                                Label("清空全部缓存", systemImage: "trash.fill")
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("已缓存歌曲")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { cacheService.refresh() }
        .confirmationDialog("清空全部缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { cacheService.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有已缓存的歌曲文件")
        }
    }
}
