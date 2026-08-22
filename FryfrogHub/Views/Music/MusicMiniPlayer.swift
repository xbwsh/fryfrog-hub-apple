import SwiftUI
import UIKit

struct MusicMiniPlayer: View {
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
