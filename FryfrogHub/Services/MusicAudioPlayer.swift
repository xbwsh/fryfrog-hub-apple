import AVFoundation
import Foundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class MusicAudioPlayer {
    static let shared = MusicAudioPlayer()

    private(set) var currentSong: MusicSong?
    private(set) var isPlaying = false
    private(set) var position: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private weak var observerPlayer: AVPlayer?
    @ObservationIgnored private var queue: [MusicSong] = []
    @ObservationIgnored private var queueIndex = 0
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    /// 暂停淡出时长（秒），可按需调整 0.4~1.0
    @ObservationIgnored private let fadeDuration: TimeInterval = 0.6
    /// 播放模式：顺序 / 循环 / 单曲 / 随机
    enum PlayMode: String, CaseIterable {
        case order   // 顺序播放 播完停止
        case loop    // 循环播放 播完回到第一首
        case single  // 单曲循环
        case shuffle // 随机播放

        var title: String {
            switch self {
            case .order: return "顺序播放"
            case .loop: return "循环播放"
            case .single: return "单曲循环"
            case .shuffle: return "随机播放"
            }
        }
        var systemImage: String {
            switch self {
            case .order: return "list.bullet"
            case .loop: return "repeat"
            case .single: return "repeat.1"
            case .shuffle: return "shuffle"
            }
        }
        func next() -> PlayMode {
            switch self {
            case .order: return .loop
            case .loop: return .single
            case .single: return .shuffle
            case .shuffle: return .order
            }
        }
    }
    private(set) var playMode: PlayMode = .order

    private init() {
        // 延迟激活：不在初始化时抢占 AVAudioSession，避免与 mpv 的 moviePlayback 互斥导致有声无画
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        let center = NotificationCenter.default
        center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded() }
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            Task { @MainActor in
                guard let self, type == .ended else { return }
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
                try? AVAudioSession.sharedInstance().setActive(true)
                if self.isPlaying {
                    self.player?.play()
                }
            }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playCurrent() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
    }

    func play(_ song: MusicSong, queue: [MusicSong] = []) {
        if !queue.isEmpty {
            self.queue = queue
            queueIndex = queue.firstIndex(of: song) ?? 0
        }
        let url: URL
        if let local = MusicCacheService.shared.localPlaybackURL(for: song) {
            url = local
        } else {
            guard let remote = song.streamURL else { return }
            url = remote
        }
        // 任何新的播放都先取消正在进行的淡出，并恢复音量
        cancelFadeAndRestoreVolume()
        if currentSong?.id != song.id {
            removeTimeObserver()
            player?.pause()
            player?.volume = 1
            player = AVPlayer(url: url)
            player?.volume = 1
            currentSong = song
            position = 0
            installTimeObserver()
        } else if player == nil {
            player = AVPlayer(url: url)
            player?.volume = 1
            installTimeObserver()
        } else if let local = MusicCacheService.shared.localPlaybackURL(for: song),
                  (player?.currentItem?.asset as? AVURLAsset)?.url != local {
            // 已有缓存后切到本地文件
            let currentTime = player?.currentTime()
            player = AVPlayer(url: local)
            player?.volume = 1
            if let currentTime { player?.seek(to: currentTime) }
            installTimeObserver()
        } else {
            // 同一首歌恢复播放时确保音量还原
            player?.volume = 1
        }
        player?.play()
        isPlaying = true
        configureNowPlaying(song)
        if MusicCacheSettings.shared.autoCacheOnPlay, !MusicCacheService.shared.isCached(song) {
            Task { try? await MusicCacheService.shared.download(song: song) }
        }
    }

    func toggle() {
        guard player != nil else { return }
        if isPlaying {
            pauseWithFade()
        } else {
            cancelFadeAndRestoreVolume()
            player?.volume = 1
            player?.play()
            isPlaying = true
            if let song = currentSong { configureNowPlaying(song) }
        }
    }

    func playCurrent() {
        guard let currentSong else { return }
        if isPlaying { return }
        cancelFadeAndRestoreVolume()
        if player == nil {
            play(currentSong)
        } else {
            player?.volume = 1
            player?.play()
            isPlaying = true
            configureNowPlaying(currentSong)
        }
    }

    func pause() {
        pauseWithFade()
    }

    /// 渐隐暂停（对外保留 pause() 的同步语义，内部用 Task 做音量斜坡）
    func pauseWithFade(duration: TimeInterval? = nil) {
        guard let player else { isPlaying = false; return }
        // 已暂停则忽略（淡出进行中再次 pause 不重复触发，避免音量跳变）
        if !isPlaying { return }
        // 立刻更新 UI 状态，但声音渐隐
        isPlaying = false
        // 锁屏/控制中心同步为暂停状态
        if let song = currentSong { configureNowPlaying(song) }
        fadeOutAndPause(player: player, duration: duration ?? fadeDuration)
    }

    /// 立即暂停（用于切歌、stop 等不需要淡出的场景）
    func pauseImmediately() {
        cancelFadeAndRestoreVolume()
        player?.pause()
        player?.volume = 1
        isPlaying = false
    }

    /// 跳转到指定秒数（用于进度条拖动）
    func seek(to seconds: Double) {
        guard let player, let duration = currentSong?.durationSeconds, duration > 0 else { return }
        let clamped = min(max(seconds, 0), duration)
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        // seek 期间保持播放状态由 isPlaying 决定
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.position = clamped }
        }
        position = clamped
        if let song = currentSong { configureNowPlaying(song) }
    }

    func updateCurrentStarred(_ starred: Bool) {
        guard let song = currentSong else { return }
        currentSong = MusicSong(
            id: song.id, title: song.title, artistName: song.artistName, albumName: song.albumName,
            artistId: song.artistId, albumId: song.albumId, trackNumber: song.trackNumber, discNumber: song.discNumber,
            durationSeconds: song.durationSeconds, format: song.format, bitRate: song.bitRate, genre: song.genre,
            year: song.year, fileSize: song.fileSize, streamUrl: song.streamUrl, coverUrl: song.coverUrl,
            lyricsUrl: song.lyricsUrl, starred: starred, rating: song.rating, playCount: song.playCount
        )
        if let updated = currentSong { configureNowPlaying(updated) }
    }

    func cyclePlayMode() {
        playMode = playMode.next()
        if let song = currentSong { configureNowPlaying(song) }
    }

    func handleTrackEnded() {
        guard !queue.isEmpty else { isPlaying = false; return }
        switch playMode {
        case .order:
            if queueIndex + 1 < queue.count {
                queueIndex += 1
                play(queue[queueIndex], queue: queue)
            } else {
                isPlaying = false
            }
        case .loop:
            queueIndex = (queueIndex + 1) % queue.count
            play(queue[queueIndex], queue: queue)
        case .single:
            // 单曲循环：原地重播
            player?.seek(to: .zero)
            player?.play()
            isPlaying = true
            if let song = currentSong { configureNowPlaying(song) }
        case .shuffle:
            guard queue.count > 1 else {
                player?.seek(to: .zero)
                player?.play()
                return
            }
            var next = queueIndex
            while next == queueIndex { next = Int.random(in: 0..<queue.count) }
            queueIndex = next
            play(queue[queueIndex], queue: queue)
        }
    }

    func playNext() {
        guard !queue.isEmpty else { isPlaying = false; return }
        switch playMode {
        case .order:
            guard queueIndex + 1 < queue.count else { isPlaying = false; return }
            queueIndex += 1
            play(queue[queueIndex], queue: queue)
        case .loop, .single:
            // 单曲循环时手动下一首仍切歌（仅自动结束时循环）
            queueIndex = (queueIndex + 1) % queue.count
            play(queue[queueIndex], queue: queue)
        case .shuffle:
            guard queue.count > 1 else { player?.seek(to: .zero); player?.play(); return }
            var next = queueIndex
            while next == queueIndex { next = Int.random(in: 0..<queue.count) }
            queueIndex = next
            play(queue[queueIndex], queue: queue)
        }
    }

    func playPrevious() {
        guard !queue.isEmpty else { player?.seek(to: .zero); return }
        switch playMode {
        case .shuffle:
            guard queue.count > 1 else { player?.seek(to: .zero); return }
            var prev = queueIndex
            while prev == queueIndex { prev = Int.random(in: 0..<queue.count) }
            queueIndex = prev
            play(queue[queueIndex], queue: queue)
        default:
            if queueIndex > 0 {
                queueIndex -= 1
                play(queue[queueIndex], queue: queue)
            } else {
                // 已是第一首：顺序/循环/单曲均回到开头
                if playMode == .loop || playMode == .single {
                    queueIndex = queue.count - 1
                    play(queue[queueIndex], queue: queue)
                } else {
                    player?.seek(to: .zero)
                }
            }
        }
    }

    func stop() {
        cancelFadeAndRestoreVolume()
        removeTimeObserver()
        player?.pause()
        player?.volume = 1
        player = nil
        isPlaying = false
        currentSong = nil
        position = 0
    }

    // MARK: - 淡入淡出

    private func fadeOutAndPause(player targetPlayer: AVPlayer, duration: TimeInterval) {
        // 取消上一次淡出（不恢复音量，避免音量跳变）
        fadeTask?.cancel()
        let startVolume = targetPlayer.volume
        // 已静音或无需淡出则直接暂停
        guard startVolume > 0.01, duration > 0.01 else {
            targetPlayer.pause()
            targetPlayer.volume = 1
            return
        }
        // 约 60fps 的平滑度：0.6s ≈ 36 步，每步 16ms 左右
        let steps = max(Int(duration * 60), 12)
        let interval = duration / Double(steps)

        fadeTask = Task { [weak self, weak targetPlayer] in
            guard let targetPlayer else { return }
            for step in 1...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                // 线性淡出；如需更柔和可改为 ease-out：pow(1 - progress, 1.2)
                let progress = Double(step) / Double(steps)
                let volume = Float(startVolume * Float(1 - progress))
                await MainActor.run {
                    // 仅当当前播放器仍是淡出目标时才改音量，避免切歌后误改新 player
                    if self?.player === targetPlayer {
                        targetPlayer.volume = max(volume, 0)
                    }
                }
            }
            await MainActor.run {
                // 再次确认未被取消且播放器未切换
                guard !(Task.isCancelled), self?.player === targetPlayer else { return }
                targetPlayer.pause()
                // 为下次播放恢复满音量（paused 状态下设置不影响当前静音效果）
                targetPlayer.volume = 1
                self?.fadeTask = nil
            }
        }
    }

    private func cancelFadeAndRestoreVolume() {
        fadeTask?.cancel()
        fadeTask = nil
        player?.volume = 1
    }

    private func installTimeObserver() {
        removeTimeObserver()
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            let value = time.seconds.isFinite ? time.seconds : 0
            Task { @MainActor in self?.position = value }
        }
        observerPlayer = player
    }

    private func removeTimeObserver() {
        guard let timeObserver, let observerPlayer else {
            self.timeObserver = nil
            self.observerPlayer = nil
            return
        }
        observerPlayer.removeTimeObserver(timeObserver)
        self.timeObserver = nil
        self.observerPlayer = nil
    }

    private func configureNowPlaying(_ song: MusicSong) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artistName ?? "未知歌手",
            MPMediaItemPropertyAlbumTitle: song.albumName ?? "未知专辑",
            MPMediaItemPropertyPlaybackDuration: song.durationSeconds ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0,
        ]
        if let coverUrl = song.coverURL {
            Task { [weak self] in
                let image = try? await AuthImageLoader.shared.loadScaled(url: coverUrl)
                guard let self, self.currentSong?.id == song.id, let image else { return }
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
                updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
