import SwiftUI
import UIKit

/// 主页顶部轮播图（横屏大图 + 自动轮播 + 无缝无限循环）
/// 点击回调交给外层处理导航，避免 navigationDestination 落在 lazy 容器内
struct CarouselView: View {
    let items: [SeriesListDTO]
    var onSelect: (SeriesListDTO) -> Void

    @State private var currentIndex = 0
    @State private var timer: Task<Void, Never>?

    var body: some View {
        Group {
            if items.count > 1 {
                InfiniteCarousel(
                    items: items,
                    currentIndex: $currentIndex,
                    onSelect: onSelect
                )
            } else if let first = items.first {
                CarouselPage(item: first) { onSelect(first) }
            }
        }
        .frame(height: 260)
        .overlay(alignment: .bottomTrailing) {
            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<items.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? .white : .white.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(14)
            }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        // 手动滑动或自动轮播切换时都重置计时
        .onChange(of: currentIndex) { _, _ in
            restartTimer()
        }
    }

    private func startTimer() {
        guard items.count > 1 else { return }
        stopTimer()
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    currentIndex = (currentIndex + 1) % items.count
                }
            }
        }
    }

    private func restartTimer() {
        startTimer()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}

/// 单页内容（大图 + 渐变 + 标题信息），点击进入详情
private struct CarouselPage: View {
    let item: SeriesListDTO
    var onSelect: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ServerImageView(path: item.fanartUrl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if !item.yearText.isEmpty {
                        Text(item.yearText)
                    }
                    Text(item.isTV ? "剧集" : "电影")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

/// 基于 UIPageViewController 的无限循环轮播：
/// 首尾各插入一张镜像页，跨边界时以无动画方式跳转到内容相同的真实页，视觉完全无缝
private struct InfiniteCarousel: UIViewControllerRepresentable {
    let items: [SeriesListDTO]
    @Binding var currentIndex: Int
    var onSelect: (SeriesListDTO) -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        context.coordinator.rebuild(in: pageVC)
        return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        context.coordinator.update(
            items: items,
            onSelect: onSelect,
            binding: $currentIndex,
            in: pageVC
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, onSelect: onSelect, binding: $currentIndex)
    }
}

private final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private var items: [SeriesListDTO]
    private var onSelect: (SeriesListDTO) -> Void
    private var binding: Binding<Int>
    private var pages: [UIViewController] = []
    /// 当前展示页在 pages 中的索引（真实页 i 对应 pages[i + 1]）
    private var pageIndex = 0
    private var transitionInProgress = false

    init(items: [SeriesListDTO], onSelect: @escaping (SeriesListDTO) -> Void, binding: Binding<Int>) {
        self.items = items
        self.onSelect = onSelect
        self.binding = binding
    }

    // MARK: - 构建

    /// 镜像页数组：`[末张镜像, 真实0, …, 真实n-1, 首张镜像]`
    private func makePages() -> [UIViewController] {
        guard !items.isEmpty else { return [] }
        let mirrored = [items[items.count - 1]] + items + [items[0]]
        return mirrored.map { item in
            UIHostingController(
                rootView: CarouselPage(item: item) { [weak self] in
                    self?.onSelect(item)
                }
            )
        }
    }

    func rebuild(in pageVC: UIPageViewController) {
        pages = makePages()
        pageIndex = 1
        if !items.isEmpty {
            pageVC.setViewControllers([pages[1]], direction: .forward, animated: false)
        }
    }

    func update(
        items: [SeriesListDTO],
        onSelect: @escaping (SeriesListDTO) -> Void,
        binding: Binding<Int>,
        in pageVC: UIPageViewController
    ) {
        self.onSelect = onSelect
        self.binding = binding
        guard items == self.items else {
            self.items = items
            rebuild(in: pageVC)
            binding.wrappedValue = 0
            return
        }
        syncPage(binding.wrappedValue, in: pageVC)
    }

    // MARK: - 页面同步（自动轮播驱动）

    private func syncPage(_ realIndex: Int, in pageVC: UIPageViewController) {
        guard !transitionInProgress, !items.isEmpty else { return }
        let targetPage = realIndex + 1
        guard targetPage != pageIndex, (1...items.count).contains(targetPage) else { return }
        jump(toPage: targetPage, in: pageVC, animated: true)
    }

    private func jump(toPage targetPage: Int, in pageVC: UIPageViewController, animated: Bool) {
        guard (0..<pages.count).contains(targetPage), targetPage != pageIndex else { return }
        pageIndex = targetPage
        pageVC.setViewControllers(
            [pages[targetPage]],
            direction: animated ? .forward : .reverse,
            animated: animated
        )
    }

    private func writeBinding(_ value: Int) {
        guard binding.wrappedValue != value else { return }
        binding.wrappedValue = value
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index > 0 else { return nil }
        return pages[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index < pages.count - 1 else { return nil }
        return pages[index + 1]
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        transitionInProgress = true
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        transitionInProgress = false
        guard completed, let current = pageViewController.viewControllers?.first,
              let index = pages.firstIndex(of: current) else { return }

        if index == 0 {
            // 滑到末尾镜像页 → 无动画跳回真实末张
            jump(toPage: items.count, in: pageViewController, animated: false)
            writeBinding(items.count - 1)
        } else if index == items.count + 1 {
            // 滑到首张镜像页 → 无动画跳回真实首张
            jump(toPage: 1, in: pageViewController, animated: false)
            writeBinding(0)
        } else {
            pageIndex = index
            writeBinding(index - 1)
        }
    }
}
