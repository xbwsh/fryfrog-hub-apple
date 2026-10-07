import SwiftUI
import UIKit

/// 有声书底部迷你播放器 — 与 MusicMiniPlayer 视觉风格统一
struct AudiobookMiniPlayer: View {
    @State private var player = AudiobookPlayerService.shared
    @State private var showingFullPlayer = false
    private let cornerRadius: CGFloat = 18

    var body: some View {
        if player.currentTrack != nil {
            let progress = player.duration > 0 ? min(max(player.currentTime / player.duration, 0), 1) : 0

            ZStack(alignment: .bottom) {
                HStack(spacing: 14) {
                    // 左侧：封面 + 信息（点击展开全屏）
                    Button(action: { showingFullPlayer = true }) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 52, height: 52)
                                if let coverUrl = player.currentBook?.coverUrl {
                                    ServerImageView(path: coverUrl)
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                                        )
                                        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                                        .id(player.currentBook?.id ?? 0) // 切书时强制刷新封面，避免旧图残留
                                } else {
                                    Image(systemName: "book.closed")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 52, height: 52)
                                }
                            }
                            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: player.currentBook?.id)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.currentBook?.title ?? "")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(player.currentTrack?.title ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 右侧控件：后退15s + 播放/暂停 + 前进15s
                    HStack(spacing: 8) {
                        Button {
                            player.seekBackward()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background { miniGlassCircle }
                                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

                        Button {
                            player.togglePlayPause()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.accentColor, in: Circle())
                                .shadow(color: Color.accentColor.opacity(0.32), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                        Button {
                            player.seekForward()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background { miniGlassCircle }
                                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .padding(.bottom, 6)

                // 底部进度条
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
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: player.currentTrack?.id)
            .sheet(isPresented: $showingFullPlayer) {
                AudiobookFullPlayerView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
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

    /// 迷你播放器圆形按钮底座 — iOS 26 液态玻璃，低版本降级为半透明
    @ViewBuilder
    private var miniGlassCircle: some View {
        if #available(iOS 26.0, *) {
            Circle().fill(.clear).glassEffect(.regular, in: .circle)
        } else {
            Circle().fill(Color.primary.opacity(0.08))
        }
    }
}

/// 有声书完整播放器视图 — 与 MusicNowPlayingView 视觉风格统一
struct AudiobookFullPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = AudiobookPlayerService.shared
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private var duration: Double { max(player.duration, 1) }

    var body: some View {
        ZStack {
            // 沉浸式背景：封面模糊 + 渐变遮罩
            nowPlayingBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // 封面
                        artworkCard
                            .padding(.top, 4)

                        // 书名和音轨信息
                        bookInfo
                            .padding(.top, 26)

                        // 进度条
                        progressSection
                            .padding(.top, 24)
                            .padding(.horizontal, 36)

                        // 控制按钮
                        controlsSection
                            .padding(.top, 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .tint(.primary)
    }

    // MARK: - 背景

    private var nowPlayingBackground: some View {
        ZStack {
            Color.appBackground
            if let coverUrl = player.currentBook?.coverUrl {
                ServerImageView(path: coverUrl)
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
            Color.clear.frame(width: 44, height: 44)
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(player.currentBook?.title ?? "有声书")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await player.saveProgress() }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background { glassCircle() }
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 封面

    private var artworkCard: some View {
        let cardSize: CGFloat = 300
        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .frame(width: cardSize, height: cardSize)
                .blur(radius: 18)
                .offset(y: 14)
                .opacity(0.9)

            if let coverUrl = player.currentBook?.coverUrl {
                ServerImageView(path: coverUrl)
                    .frame(width: cardSize, height: cardSize)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                    .scaleEffect(player.isPlaying ? 1.0 : 0.97)
                    .animation(.spring(response: 0.5, dampingFraction: 0.78), value: player.isPlaying)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: cardSize, height: cardSize)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 书名信息

    private var bookInfo: some View {
        VStack(spacing: 5) {
            Text(player.currentBook?.title ?? "")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 420)

            HStack(spacing: 5) {
                Image(systemName: "book.closed")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.32))
                Text(player.currentTrack?.title ?? "")
                    .foregroundStyle(.white.opacity(0.84))
                if let narrator = player.currentBook?.narrator, !narrator.isEmpty {
                    Text("·").foregroundStyle(.white.opacity(0.32))
                    Text(narrator).foregroundStyle(.white.opacity(0.56)).lineLimit(1)
                }
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
        }
        .frame(maxWidth: 420)
    }

    // MARK: - 进度条

    private var progressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let total = duration
                let position = isDragging ? dragValue : player.currentTime
                let progress = total > 0 ? min(max(position / total, 0), 1) : 0
                let dotSize: CGFloat = isDragging ? 14 : 10
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * progress, height: 4)
                    Circle()
                        .fill(Color.white)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: .black.opacity(0.24), radius: 4, y: 1)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .offset(x: max(0, geo.size.width * progress - dotSize / 2))
                        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isDragging)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging { isDragging = true }
                            let x = min(max(value.location.x, 0), geo.size.width)
                            let pct = geo.size.width > 0 ? x / geo.size.width : 0
                            dragValue = Double(pct) * total
                        }
                        .onEnded { _ in
                            player.seek(to: dragValue)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isDragging = false }
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(formatTime(isDragging ? dragValue : player.currentTime))
                    .contentTransition(.numericText())
                Spacer()
                Text("-\(player.remainingTimeText)")
                    .foregroundStyle(.white.opacity(0.62))
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: 420)
    }

    // MARK: - 控制按钮

    private var controlsSection: some View {
        VStack(spacing: 14) {
            // 倍速控制
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        player.setPlaybackRate(Float(rate))
                    } label: {
                        HStack {
                            Text(String(format: "%.2gx", rate))
                            if player.playbackRate == Float(rate) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .semibold))
                    Text(String(format: "%.1gx", player.playbackRate))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.5)
                }
                .foregroundStyle(player.playbackRate == 1.0 ? Color.white : Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background { glassCapsule() }
                .overlay(Capsule().stroke(Color.white.opacity(player.playbackRate == 1.0 ? 0.10 : 0.20), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                // 后退 15 秒
                Button {
                    player.seekBackward()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background { glassCircle() }
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer().frame(width: 28)

                // 播放 / 暂停
                Button {
                    player.togglePlayPause()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)
                            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.black)
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(player.isPlaying ? 1.0 : 1.02)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: player.isPlaying)

                Spacer().frame(width: 28)

                // 前进 15 秒
                Button {
                    player.seekForward()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background { glassCircle() }
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 工具

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
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

#Preview {
    AudiobookMiniPlayer()
}
