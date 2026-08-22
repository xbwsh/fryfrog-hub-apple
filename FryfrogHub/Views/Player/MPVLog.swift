import Foundation

/// 简单文件日志：追加写入 App Documents/mpv.log，便于排查播放器问题
enum MPVLog {
    private static let lock = NSLock()
    private static var handle: FileHandle?

    private static func fileURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("mpv.log")
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        handle?.closeFile()
        handle = nil
        if let url = fileURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(Date()) [mpv] \(message)\n"
        guard let url = fileURL() else { return }
        if handle == nil {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
        }
        guard let data = line.data(using: .utf8) else { return }
        handle?.seekToEndOfFile()
        handle?.write(data)
    }
}
