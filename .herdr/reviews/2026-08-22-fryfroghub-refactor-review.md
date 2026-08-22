# 代码审查单 — FryfrogHub 重构（Phase 0-3）

**审查日期**: 2026-08-22  
**审查者**: 审查者 Agent  
**提交摘要**: Phase 0 基建、Phase 1 并发/崩溃修复、Phase 2 巨型文件拆分、Phase 3 代码隐患收敛

---

## 一、审查范围总览

| 维度 | 文件/区域 | 审查结论 |
|------|-----------|----------|
| 并发原语 | `AsyncSemaphore.swift` | ✅ 通过 |
| 事件循环改造 | `MpvPlayer.swift:417-483` | ✅ 通过 |
| 错误传导链 | `MpvMetalView` → `MpvMetalViewContainer` → `handleRenderFailure` | ✅ 通过 |
| 本地状态同步 | `MusicService.setStar` + `MusicModels.updating()` | ⚠️ 1 建议 |
| 拆分文件抽查 | `MusicNowPlayingView`、`UsersManagementView`、`LyricsLine`、`EpisodeDisplayMode` | ✅ 纯搬运 |
| 基建配置 | `.gitignore`、`project.yml`、`ServerImageView` | ✅ 通过 |
| 存量修复 | `CalendarView`、`MusicAudioPlayer`、`APIConfig`、`LoginViewModel` | ✅ 通过 |

---

## 二、重点审查项详评

### 2.1 AsyncSemaphore.swift — 并发原语

**结论: ✅ 实现正确，无阻塞风险**

- `wait()` 在 actor 内执行，`withCheckedContinuation` 的闭包同步追加 continuation 到 `waiters` 数组，无跨 actor 状态竞争。
- `signal()` 逻辑完备：有排队者时直接 `resume()` 移交许可（`available` 不变），无排队者时 `available += 1`，许可不泄漏。
- `withPermit` 在 `do`/`catch` 两个分支均调用 `signal()`，配合 `rethrows`，异常路径归还正确。
- 设计为"不感知取消"策略（被取消的任务仍排队、获许可后由后续操作抛错），文档已明确说明，符合预期。

### 2.2 MpvPlayer.swift 事件循环改造（417-483 行）

**结论: ✅ 行为等价，竞态风险已消除**

- `RunningFlag` 使用 `NSLock` 保护，`shutdown()` 置 false 与事件线程轮询读取之间线程安全。
- `handleEvent` 声明为 `nonisolated`，函数体内仅做 C 内存读取（`event.pointee`）和日志，不触碰 `@MainActor` 隔离状态。
- **关键改进**: 属性值在事件线程内通过 `PropertyValue.decode()` 解码为 Sendable 值类型后，经 `DispatchQueue.main.async` 传主线程。消除了旧实现中主线程延迟读取 `mpv_event.data` 悬垂指针的竞态。
- `shutdown()` 使用 `eventLoopStopped.wait(timeout: .now() + 1)` 等待事件线程退出，最长阻塞 1s，不阻塞 Swift 协作线程池。
- `EventContext` 标记 `@unchecked Sendable`，`OpaquePointer` 仅在事件线程内解包，生命周期由 `shutdown()` 的退出同步保证。
- `Thread.detachNewThread` 的 `defer { self?.eventLoopStopped.signal() }` 保证事件线程退出时必定信号，不泄漏。

### 2.3 MpvMetalView → MpvMetalViewContainer → handleRenderFailure 错误传导链

**结论: ✅ 错误传导完整，用户可观测**

1. `MpvMetalView.init?` 在 Metal 设备缺失/命令队列失败/着色器编译失败/管线创建失败时返回 `nil`，记录日志。
2. `MpvMetalViewContainer.makeUIView` 检测到 `nil` 后：
   - 延迟到下一 runloop 通过 `onFailure` 回报（避免视图构建期间修改 SwiftUI 状态）
   - 返回空 `UIView()` 作为占位
3. `MpvVideoPlayerView.handleRenderFailure` 存储错误消息，由 `.overlay` 中的错误 UI 展示（感叹号图标 + 文案）。

传导链完整，无遗漏路径。

### 2.4 MusicService.setStar 重写 + MusicModels.updating()

**结论: ⚠️ 功能正确，存在架构建议**

**setStar 三分支本地同步逻辑**:
- `songs` 分支: 更新 `songs` 数组中对应项 + `selectedAlbum.songs` 中对应项，语义正确。
- `albums` 分支: 更新 `groups` 中每个 group 的 albums + `selectedAlbum` 本身，语义正确。
- `artists` 分支: 更新 `groups` 中每个 group 的 artists + `selectedArtist` 本身，语义正确。

**updating() 方法族**:
- `MusicAlbum.updating(starred:)` / `MusicAlbum.updating(songs:)` / `MusicArtist.updating(starred:)` / `MusicSong.updating(starred:)` / `MusicLibraryGroup.updating(albums:)` / `MusicLibraryGroup.updating(artists:)` 均为纯值拷贝，正确。

**⚠️ 建议 (非阻塞)**:
`MusicService` 是 `@Observable` 类但未标注 `@MainActor`。`setStar` 内部用 `MainActor.run` 包裹状态更新，实践中安全。但其他可能修改状态的方法（如 `loadHome`、`reload`、`loadSongs`）均标记 `async`，调用者需自行保证主线程。建议后续统一为 `@MainActor` 或在每个状态变更方法中加 `MainActor.run`，以消除潜在竞态隐患。

---

## 三、拆分文件抽查

| 文件 | 抽查结论 |
|------|----------|
| `LyricsLine.swift` | 纯类型定义搬运（8 行），无逻辑变更 |
| `MusicNowPlayingView.swift` | 从 `MusicView` 抽出的完整 UI 代码（708 行），逻辑无漂移 |
| `UsersManagementView.swift` | 从 `ProfileView` 抽出的用户管理视图（237 行），逻辑无漂移 |
| `EpisodeDisplayMode.swift` | 从 `SeriesDetailView` 抽出的枚举定义（28 行），逻辑无漂移 |

---

## 四、基建/配置审查

### .gitignore
覆盖 Xcode 构建产物、SwiftPM、AI 工具链、诊断输出，完整。

### project.yml
- `ALWAYS_SEARCH_USER_PATHS: NO` 消除传统 headermap 警告
- `UIRequiresFullScreen: true` 声明全屏，符合媒体播放器定位
- `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` 与新增 `AccentColor.colorset` 匹配
- 框架嵌入脚本处理 simulator/device 分支，`codesign` 失败静默（兼容无签名环境）

### ServerImageView.swift (DispatchSemaphore → AsyncSemaphore)
- `AuthImageLoader.downloadGate` 从 `DispatchSemaphore(limit: 4)` 替换为 `AsyncSemaphore(limit: 4)`
- `loadScaled` 中使用 `downloadGate.withPermit { ... }`，挂起式限流，不阻塞协作线程池
- 正确。

---

## 五、存量修复抽查

| 文件 | 修改点 | 结论 |
|------|--------|------|
| `CalendarView.swift` | 小修（隐私过滤等） | ✅ 无异常 |
| `MusicAudioPlayer.swift` | 小修（存量告警清零） | ✅ 无异常 |
| `APIConfig.swift` | `MainActor.run` 统一跳主线程 + `HostValidator` | ✅ IPv6 括号补齐逻辑正确 |
| `LoginViewModel.swift` | `HostValidator.isValid` 复用 | ✅ 去重正确 |

---

## 六、总结

| 评级 | 说明 |
|------|------|
| **整体** | ✅ **通过** |

**核心改进确认**:
1. AsyncSemaphore 替换 DispatchSemaphore — 消除协作线程池阻塞风险 ✅
2. MpvPlayer 事件循环 PropertyValue 解码前移 — 消除悬垂指针竞态 ✅
3. MpvMetalView 可失败初始化 — 消除 try!/fatalError 崩溃 ✅
4. MusicService.setStar 本地同步收敛 — updating() 方法族减少逐字段拷贝 ✅
5. 20 个文件纯搬运拆分 — 抽查无逻辑漂移 ✅

**建议跟进（非阻塞）**:
- `MusicService` 考虑添加 `@MainActor` 隔离，统一状态变更安全性
