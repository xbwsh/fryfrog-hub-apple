import Foundation
import AVFoundation
import Observation

/// 有声书播放器服务：基于 AVFoundation 的音频播放
@MainActor
@Observable
final class AudiobookPlayerService: NSObject {
    static let shared = AudiobookPlayerService()

    private let client: any APIClientProtocol
    private var player: AVPlayer?
    private var timeObserver: Any?

    private(set) var isPlaying = false
    private(set) var currentBookId: Int64?
    private(set) var currentTrack: AudiobookTrackDTO?
    private(set) var currentBook: AudiobookDetailDTO?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var playbackRate: Float = 1.0

    /// 播放状态变化回调
    var onPlaybackStateChanged: ((Bool) -> Void)?

    init(client: any APIClientProtocol = APIClient.shared) {
        self.client = client
        super.init()
    }

    // MARK: - 播放控制

    func play(book: AudiobookDetailDTO, track: AudiobookTrackDTO) {
        // 如果是同一本书的同一轨，直接恢复播放
        if currentBookId == book.id, currentTrack?.id == track.id {
            resume()
            return
        }

        // 停止当前播放
        stop()

        currentBookId = book.id
        currentBook = book
        currentTrack = track

        guard let streamURL = track.streamURL else {
            AppLog.networking.error("音轨流地址无效: streamUrl=\(String(describing: track.streamUrl))")
            return
        }

        AppLog.networking.info("有声书播放: \(streamURL.absoluteString)")

        // 激活音频会话
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        let playerItem = AVPlayerItem(url: streamURL)
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = false
        player?.rate = playbackRate

        // 监听播放状态
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        playerItem.addObserver(self, forKeyPath: "error", options: [.new], context: nil)

        // 添加时间观察
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
                self?.duration = playerItem.duration.seconds
            }
        }

        // 监听播放完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        player?.play()
        isPlaying = true
        onPlaybackStateChanged?(true)
    }

    func playChapter(book: AudiobookDetailDTO, chapter: AudiobookChapterDTO) {
        guard let tracks = book.tracks,
              let trackIndex = chapter.trackIndex,
              trackIndex < tracks.count else { return }

        let track = tracks[trackIndex]
        play(book: book, track: track)

        // 如果章节有起始位置，跳转到对应位置
        if let startInTrack = chapter.startInTrack, startInTrack > 0 {
            seek(to: startInTrack)
        }
    }

    func resume() {
        player?.play()
        isPlaying = true
        onPlaybackStateChanged?(true)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        onPlaybackStateChanged?(false)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func stop() {
        // 移除 KVO 观察
        if let playerItem = player?.currentItem {
            playerItem.removeObserver(self, forKeyPath: "status")
            playerItem.removeObserver(self, forKeyPath: "error")
        }

        player?.pause()
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        player = nil
        timeObserver = nil
        isPlaying = false
        currentBookId = nil
        currentTrack = nil
        currentBook = nil
        currentTime = 0
        duration = 0
        onPlaybackStateChanged?(false)
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time)
        currentTime = seconds
    }

    func seekForward(seconds: Double = 15) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }

    func seekBackward(seconds: Double = 15) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    // MARK: - 进度保存

    func saveProgress() async {
        guard let bookId = currentBookId,
              let trackIndex = currentTrack?.trackIndex else { return }

        do {
            try await AudiobookService.shared.updateProgress(
                id: bookId,
                trackIndex: trackIndex,
                positionSeconds: currentTime
            )
        } catch {
            AppLog.networking.warning("保存有声书进度失败: \(error)")
        }
    }

    // MARK: - 恢复播放位置

    func restorePosition(for book: AudiobookDetailDTO) {
        guard let progress = book.progress,
              let tracks = book.tracks,
              let trackIndex = progress.trackIndex,
              trackIndex < tracks.count else { return }

        let track = tracks[trackIndex]
        play(book: book, track: track)

        if let position = progress.positionSeconds {
            seek(to: position)
        }
    }

    // MARK: - 播放完成

    @objc private func playerDidFinishPlaying() {
        isPlaying = false
        onPlaybackStateChanged?(false)

        // 自动保存进度
        Task {
            await saveProgress()
        }
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let playerItem = object as? AVPlayerItem else { return }

        if keyPath == "status" {
            switch playerItem.status {
            case .readyToPlay:
                AppLog.networking.info("有声书播放器就绪")
            case .failed:
                AppLog.networking.error("有声书播放失败: \(playerItem.error?.localizedDescription ?? "未知错误")")
                Task { @MainActor in
                    self.isPlaying = false
                    self.onPlaybackStateChanged?(false)
                }
            case .unknown:
                break
            @unknown default:
                break
            }
        } else if keyPath == "error" {
            AppLog.networking.error("有声书播放错误: \(playerItem.error?.localizedDescription ?? "未知错误")")
        }
    }

    // MARK: - 格式化时间

    var currentTimeText: String {
        formatTime(currentTime)
    }

    var durationText: String {
        formatTime(duration)
    }

    var remainingTimeText: String {
        formatTime(max(0, duration - currentTime))
    }

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
}
