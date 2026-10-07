import SwiftUI
import UIKit
import Foundation

struct MusicNowPlayingView: View {
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
            // 左侧占位（与右侧菜单对称），标题保持居中
            Color.clear.frame(width: 44, height: 44)

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
                    .background { glassCircle() }
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
                    glassCapsule()
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
                        .padding(.horizontal, 36)

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
                // 封面四角信息：液态玻璃风格
                .overlay(alignment: .topLeading) {
                    if let song = audioPlayer.currentSong, MusicCacheService.shared.isCached(song) {
                        Label("已缓存", systemImage: "arrow.down.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background { glassCapsule() }
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
                            .background { glassCapsule() }
                            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                            .padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        if audioPlayer.isPlaying {
                            ZStack {
                                glassCircle()
                                    .frame(width: 28, height: 28)
                                Image(systemName: "waveform")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                            .padding(12)
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                                    removal: .scale(scale: 0.5).combined(with: .opacity)
                                )
                            )
                            .id("playing-badge")
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: audioPlayer.isPlaying)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        // 点击封面切换到歌词
        .onTapGesture {
            guard hasLyrics else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showLyrics = true }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .accessibilityHint("点击查看歌词")
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

    private var hasLyrics: Bool {
        if let parsedLyrics, !parsedLyrics.isEmpty { return true }
        if let lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    /// 歌词行：纯文本居中，当前句加粗放大（指示由中央固定线完成）。
    /// 点击仅限歌词文字（不设 contentShape 整行矩形），空白处点击交给外层返回封面手势
    private func lyricsRow(_ line: LyricsLine) -> some View {
        let isCurrent = line.id == currentLyricIndex
        return Text(line.text.isEmpty ? "♪" : line.text)
            .font(isCurrent ? .system(size: 22, weight: .bold, design: .rounded) : .system(size: 17, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.38))
            .shadow(color: isCurrent ? Color.black.opacity(0.30) : .clear, radius: 10, y: 4)
            .scaleEffect(isCurrent ? 1.04 : 1.0)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 44)
            .padding(.vertical, 2)
            .onTapGesture {
                audioPlayer.seek(to: line.time)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .id(line.id)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: currentLyricIndex)
    }

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
        .contentShape(Rectangle())
        // 点击歌词区域空白处切换到封面（歌词行自身点击仍用于 seek/跳转）
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showLyrics = false }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .accessibilityHint("点击空白处返回封面")
    }

    private var lyricsView: some View {
        Group {
            if let parsedLyrics, !parsedLyrics.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 18) {
                            Color.clear.frame(height: 28)
                            ForEach(parsedLyrics) { line in
                                lyricsRow(line)
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

    // MARK: - 液态玻璃

    @ViewBuilder
    private func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            Circle().fill(.clear).glassEffect(.regular, in: .circle)
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }
}
