import SwiftUI

/// 设置封面：生成截帧候选并选择
/// 电影：候选帧可设为竖屏封面或横屏背景图；剧集：用单集截帧设置系列横屏背景图
struct CoverSelectView: View {
    enum Mode {
        /// 电影：截帧设置为自身封面/背景图
        case movie(videoId: Int64)
        /// 剧集：用指定单集的截帧设置系列横屏背景图
        case series(seriesId: Int64, videoId: Int64)
    }

    let mode: Mode
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var hasCandidates = false
    @State private var isGenerating = false
    @State private var pendingIndex: Int?
    @State private var errorMessage: String?

    private let service = VideoService.shared

    private var videoId: Int64 {
        switch mode {
        case .movie(let id): return id
        case .series(_, let id): return id
        }
    }

    private var prompt: String {
        switch mode {
        case .movie:
            return "生成候选截帧后，选择一张作为竖屏封面或横屏背景图"
        case .series:
            return "用剧集截帧设置系列的横屏背景图"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if isGenerating {
                    Spacer()
                    ProgressView("正在生成截帧…")
                    Spacer()
                } else if hasCandidates {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(0..<6, id: \.self) { index in
                                Button {
                                    pendingIndex = index
                                } label: {
                                    ServerImageView(path: "/api/v1/video/\(videoId)/frames/\(index)")
                                        .aspectRatio(16 / 9, contentMode: .fill)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(alignment: .bottomLeading) {
                                            Text("候选 \(index + 1)")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.black.opacity(0.6), in: Capsule())
                                                .padding(6)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    Spacer()
                    ContentUnavailableView(
                        "尚未生成候选帧",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("点击下方按钮生成 6 个候选截帧")
                    )
                    Spacer()
                }

                Button {
                    Task { await generate() }
                } label: {
                    Label(hasCandidates ? "重新生成" : "生成候选帧", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 12)
                .disabled(isGenerating)
            }
            .padding(.vertical)
            .background(Color.appBackground)
            .navigationTitle("设置封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "选择截帧",
                isPresented: Binding(
                    get: { pendingIndex != nil },
                    set: { if !$0 { pendingIndex = nil } }
                ),
                titleVisibility: .visible
            ) {
                switch mode {
                case .movie:
                    Button("设为竖屏封面") { Task { await select(type: "poster") } }
                    Button("设为横屏背景图") { Task { await select(type: "fanart") } }
                case .series:
                    Button("设为系列背景图") { Task { await select(type: "fanart") } }
                }
                Button("取消", role: .cancel) { pendingIndex = nil }
            } message: {
                Text("选定该截帧作为封面。")
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            try await service.generateFrames(videoId: videoId)
            hasCandidates = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(type: String) async {
        guard let index = pendingIndex else { return }
        pendingIndex = nil
        do {
            switch mode {
            case .movie(let videoId):
                try await service.selectFrame(videoId: videoId, index: index, type: type)
            case .series(let seriesId, let videoId):
                try await service.selectSeriesFanart(seriesId: seriesId, videoId: videoId, index: index)
            }
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    CoverSelectView(mode: .movie(videoId: 1)) {}
}
