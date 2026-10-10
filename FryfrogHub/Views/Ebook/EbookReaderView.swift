import SwiftUI
import PDFKit
import WebKit

/// 电子书阅读器入口：按格式分发 PDF / EPUB 阅读器，其余格式降级为分享打开
struct EbookReaderView: View {
    let book: EbookDetailDTO
    let fileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var positionPercent: Double
    @State private var lastReportedAt = Date.distantPast
    @State private var lastReportedPercent: Double = -1

    init(book: EbookDetailDTO, fileURL: URL) {
        self.book = book
        self.fileURL = fileURL
        _positionPercent = State(initialValue: book.progress?.positionPercent ?? 0)
    }

    var body: some View {
        NavigationStack {
            Group {
            switch book.format {
            case "PDF":
                EbookPdfReaderView(
                    book: book,
                    url: fileURL,
                    initialPercent: positionPercent,
                    onProgress: { report($0) }
                )
            case "EPUB":
                EbookEpubReaderView(
                    book: book,
                    url: fileURL,
                    initialPercent: positionPercent,
                    onProgress: { report($0) }
                )
            case "TXT":
                // 在线阅读：不依赖 fileURL（正文/目录走独立接口）
                EbookTxtReaderView(book: book) { percent, chapterIndex in
                    report(percent, chapterIndex: chapterIndex)
                }
                default:
                    fallbackView
                }
            }
            .background(Color.appBackground)
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(String(format: "%.0f%%", positionPercent))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// MOBI/AZW3 等：分享给其他应用打开
    private var fallbackView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("该格式暂不支持应用内阅读")
                .foregroundStyle(.secondary)
            ShareLink(item: fileURL) {
                Label("下载 / 用其他应用打开", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 节流上报：间隔 ≥3s 或变化 ≥5% 才发请求。
    /// chapterIndex 优先用调用方传入（TXT 在线阅读的实时全局章序）；PDF/EPUB 不传，沿用已保存进度里的章节。
    private func report(_ percent: Double, chapterIndex: Int? = nil) {
        positionPercent = percent
        let now = Date()
        if now.timeIntervalSince(lastReportedAt) >= 3 || abs(percent - lastReportedPercent) >= 5 {
            lastReportedAt = now
            lastReportedPercent = percent
            let chapter = chapterIndex ?? book.progress?.chapterIndex
            Task {
                try? await EbookService.shared.updateProgress(
                    id: book.id, positionPercent: percent, chapterIndex: chapter
                )
            }
        }
    }
}

// MARK: - PDF（PDFKit）

private struct EbookPdfReaderView: UIViewRepresentable {
    let book: EbookDetailDTO
    let url: URL
    let initialPercent: Double
    let onProgress: (Double) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground

        func applyDocument(_ document: PDFDocument) {
            DispatchQueue.main.async {
                view.document = document
                if initialPercent > 0, document.pageCount > 0 {
                    let index = min(document.pageCount - 1,
                                    Int(Double(document.pageCount) * initialPercent / 100))
                    if let page = document.page(at: index) {
                        view.go(to: page)
                    }
                }
            }
        }

        let expectedSize = book.fileSize
        if let cached = EbookFileCache.cachedFile(for: book, expectedSize: expectedSize),
           let document = PDFDocument(url: cached) {
            applyDocument(document)
            return view
        }
        URLSession.shared.downloadTask(with: url) { location, _, _ in
            guard let location else { return }
            do {
                let saved = try EbookFileCache.save(from: location, for: book)
                if let document = PDFDocument(url: saved) {
                    applyDocument(document)
                }
            } catch {
                NSLog("[EbookReader] pdf download failed: \(error)")
            }
        }.resume()

        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: EbookPdfReaderView
        weak var pdfView: PDFView?
        init(_ parent: EbookPdfReaderView) { self.parent = parent }

        @objc func pageChanged() {
            guard let view = pdfView, let document = view.document,
                  document.pageCount > 0,
                  let current = view.currentPage else { return }
            let index = document.index(for: current)
            parent.onProgress(Double(index + 1) / Double(document.pageCount) * 100)
        }
    }
}

// MARK: - EPUB（WKWebView + epub.js）

private struct EbookEpubReaderView: UIViewRepresentable {
    let book: EbookDetailDTO
    let url: URL
    let initialPercent: Double
    let onProgress: (Double) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "reader")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        context.coordinator.webView = webView
        context.coordinator.load(url: url, initialPercent: initialPercent)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let parent: EbookEpubReaderView
        weak var webView: WKWebView?
        init(_ parent: EbookEpubReaderView) { self.parent = parent }

        /// 把 epub 下载到临时目录，连同 JS 库与 reader.html 一起以 file:// 加载
        func load(url: URL, initialPercent: Double) {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("epub-reader-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // JS 库从 bundle 拷贝到可读目录（兼容带/不带 Reader 子目录、带/不带 .min 命名）
            let jsNames = [("epub.min", "epub"), ("jszip.min", "jszip")]
            for (resourceName, targetName) in jsNames {
                let target = dir.appendingPathComponent("\(targetName).min.js")
                if let src = Bundle.main.url(forResource: resourceName, withExtension: "js", subdirectory: "Reader")
                    ?? Bundle.main.url(forResource: resourceName, withExtension: "js") {
                    try? FileManager.default.copyItem(at: src, to: target)
                }
            }

            let html = readerHTML(initialPercent: initialPercent)
            try? html.data(using: .utf8)?.write(to: dir.appendingPathComponent("reader.html"))

            let target = dir.appendingPathComponent("book.epub")
            // 复用本地缓存，避免每次打开重复下载整本书
            if let cached = EbookFileCache.cachedFile(for: parent.book, expectedSize: parent.book.fileSize) {
                try? FileManager.default.copyItem(at: cached, to: target)
                self.webView?.loadFileURL(dir.appendingPathComponent("reader.html"),
                                          allowingReadAccessTo: dir)
                return
            }
            URLSession.shared.downloadTask(with: url) { location, _, _ in
                guard let location else { return }
                do {
                    let saved = try EbookFileCache.save(from: location, for: self.parent.book)
                    try FileManager.default.copyItem(at: saved, to: target)
                    DispatchQueue.main.async {
                        self.webView?.loadFileURL(dir.appendingPathComponent("reader.html"),
                                                  allowingReadAccessTo: dir)
                    }
                } catch {
                    NSLog("[EbookReader] epub download move failed: \(error)")
                }
            }.resume()
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "reader",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            if type == "progress",
               let percent = body["percent"] as? Double {
                parent.onProgress(percent)
            } else if type == "log", let text = body["text"] as? String {
                NSLog("[EbookReader] \(text)")
            }
        }

        private func readerHTML(initialPercent: Double) -> String {
            """
            <!DOCTYPE html>
            <html><head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
            <style>
              html,body{margin:0;padding:0;height:100%;background:#fff}
              #viewer{width:100%;height:100%}
            </style>
            <script src="jszip.min.js"></script>
            <script src="epub.min.js"></script>
            </head>
            <body>
            <div id="viewer"></div>
            <script>
              var savedPercent = \(initialPercent) / 100.0;
              var reported = -1;
              function post(obj){ try{ webkit.messageHandlers.reader.postMessage(obj); }catch(e){} }
              function log(text){ post({type:"log", text:text}); }

              var book = ePub("book.epub");
              var rendition = book.renderTo("viewer", {width:"100%", height:"100%", spread:"none", flow:"paginated"});
              rendition.on("relocated", function(location){
                var percent = location.start.percentage * 100;
                if (Math.abs(percent - reported) >= 0.5) {
                  reported = percent;
                  post({type:"progress", percent: percent, chapter: location.start.index});
                }
              });
              rendition.display().then(function(){
                if (savedPercent > 0.001) {
                  book.ready.then(function(){ return book.locations.generate(1024); }).then(function(){
                    rendition.display(savedPercent);
                  });
                }
              });
            </script>
            </body></html>
            """
        }
    }
}

/// 电子书文件本地缓存：按书 id 存到 caches 目录，避免每次打开重复下载整本书。
/// 文件被服务器替换（大小变化）时自动重新下载覆盖。
private enum EbookFileCache {
    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("EbookCache", isDirectory: true)
    }

    static func fileURL(for book: EbookDetailDTO) -> URL {
        let ext = (book.format ?? "").lowercased().replacingOccurrences(of: ".", with: "")
        return directory.appendingPathComponent("\(book.id).\(ext.isEmpty ? "book" : ext)")
    }

    /// 命中有效缓存（非空且与服务器文件大小一致）时返回本地 URL
    static func cachedFile(for book: EbookDetailDTO, expectedSize: Int64?) -> URL? {
        let url = fileURL(for: book)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > 0 else { return nil }
        if let expectedSize, expectedSize > 0, size != expectedSize { return nil }
        return url
    }

    /// 把临时下载文件存入缓存目录
    static func save(from tempURL: URL, for book: EbookDetailDTO) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = fileURL(for: book)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        if fm.fileExists(atPath: tempURL.path) {
            try fm.moveItem(at: tempURL, to: dest)
            return dest
        }
        throw URLError(.fileDoesNotExist)
    }
}
