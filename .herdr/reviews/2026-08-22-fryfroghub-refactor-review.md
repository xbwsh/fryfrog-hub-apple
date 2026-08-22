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

---

## 七、Phase 3 轮次审查（e514b32..7a116cc，4 提交）

**审查日期**: 2026-08-22  
**审查者**: 审查者 Agent（只读）  
**模拟器**: 1DE872C2  
**审查范围**: T3-1 `a85e1be`、T3-2 `ef06b2c`、T3-3 `7a3b79b`、T3-6 `5ac3788`

---

### 7.1 T3-1：网络层协议抽象 + 构造注入（`a85e1be`）

#### `APIClientProtocol` — 协议定义 (`APIClient.swift:5-27`)

✅ 协议声明 7 项要求，全部 `async`：
- `setToken(_:)` / `currentToken` — token 生命周期
- `setUnauthorizedHandler(_:)` / `setForbiddenHandler(_:)` — 全局错误回调注入
- `request(_:method:body:queryItems:)` — 泛型请求（含完整 4 参数签名）
- `requestVoid(_:method:body:queryItems:)` — 无返回值请求

**无默认参数泄漏**: 协议要求本身不含默认参数值，符合 Swift 协议设计约束。

#### 6 重载扩展 (`APIClient.swift:31-68`)

✅ 重载清单（经 `extension APIClientProtocol` 补齐，转发到完整要求）：

| 重载签名 | 转发目标 | 默认值 |
|----------|----------|--------|
| `request(_ path:)` | `request(path, method:"GET", body:nil, queryItems:[])` | GET, nil, [] |
| `request(_ path:, method:)` | `request(path, method, body:nil, queryItems:[])` | nil, [] |
| `request(_ path:, queryItems:)` | `request(path, method:"GET", body:nil, queryItems:)` | GET, nil |
| `request(_ path:, method:, body:)` | `request(path, method, body, queryItems:[])` | [] |
| `request(_ path:, method:, queryItems:)` | `request(path, method, body:nil, queryItems:)` | nil |
| `requestVoid(_ path:, method:)` | `requestVoid(path, method, body:nil, queryItems:[])` | nil, [] |

6 重载覆盖现有调用面所有组合，无遗漏。

#### `APIClient` 构造注入 (`APIClient.swift:83-92`)

✅ `init(server:sessionConfiguration:)` 接受 `any ServerConnectionProtocol` + `URLSessionConfiguration`：
- 生产: `APIClient.shared` 使用默认参数（`ServerConnection.shared` + `.default`）
- 测试: 注入 `MockServerConnection` + 挂 `StubURLProtocol` 的 `.ephemeral` 配置
- `server` 属性声明为 `private let`，不可外部篡改

#### `ServerConnectionProtocol` (`APIConfig.swift:31-52`)

✅ 协议 10 项要求 + 1 扩展默认值（`probeLAN()` 无参糖），覆盖连接模式、URL 构造、探测、切换全链路。

---

### 7.2 T3-2：单元测试（`ef06b2c`）

#### 测试基础设施 (`TestSupport.swift`)

| 组件 | 职责 | 线程安全 |
|------|------|----------|
| `FlagBox` | 异步回调布尔旗标 | ✅ `NSLock` 保护 |
| `StubURLProtocol` | 按 host 路由的确定性网络桩 | ✅ `NSLock` 保护 `behaviors`/`requestedHosts` |
| `MockServerConnection` | `ServerConnectionProtocol` 替身 | ✅ 值类型属性，无并发写 |

`StubURLProtocol` 支持两种 Outcome：
- `.success(Int, String)` — 指定状态码 + JSON 体
- `.failure(URLError.Code)` — 模拟连接级失败

未登记的 host 一律返回 `.unsupportedURL` 失败，保证确定性。

#### `APIClientFallbackTests` — 边界覆盖 (`APIClientFallbackTests.swift`)

| 测试用例 | 覆盖边界 | 结论 |
|----------|----------|------|
| `test_fallback_switchesToAlternateOnPrimaryConnectionFailure` | 主地址连接失败 → 备选成功 → 切换生效模式 | ✅ |
| `test_fallback_throwsOriginalErrorWhenBothFail` | 双失败 → 抛原始错误、不切换 | ✅ |
| `test_noFallbackOnBusinessError` | 500 业务错误 → 不尝试备选 | ✅ |
| `test_noFallbackWhenAlternateNotConfigured` | 无备选地址 → 仅请求主地址 | ✅ |
| `test_unauthorizedHandlerFiresOn401` | 业务接口 401 → 触发 handler | ✅ |
| `test_unauthorizedHandlerSkippedForAuthPaths` | `/auth/login` 401 → 不触发登出 | ✅ |
| `test_forbiddenHandlerFiresOn403` | 403 → forbiddenHandler 触发、unauthorizedHandler 不触发 | ✅ |

#### `ServerConnectionTests` — 探测/切换分支 (`ServerConnectionTests.swift`)

| 测试用例 | 覆盖边界 | 结论 |
|----------|----------|------|
| `test_probeLAN_returnsTrueWhenReachable` | 局域网可达 → true | ✅ |
| `test_probeLAN_returnsFalseWhenUnreachable` | 超时 → false | ✅ |
| `test_probeLAN_returnsFalseWithoutLANHost` | 未配置 LAN → false | ✅ |
| `test_refreshActiveMode_prefersLANWhenProbeSucceeds` | 探测成功 → 切 LAN | ✅ |
| `test_refreshActiveMode_fallsBackToPublicWhenProbeFails` | 探测失败 → 切公网 | ✅ |
| `test_refreshActiveMode_forcesPublicWhenNoLANConfigured` | 无 LAN 配置 → 强制公网 | ✅ |
| `test_effectiveMode_forcesPublicWithoutLAN` | activeMode=.lan 但无 LAN → effectiveMode=.public | ✅ |
| `test_baseURL_nilWhenNothingConfigured` | 空配置 → baseURL nil | ✅ |

**隔离验证**: `ServerConnection(defaults:)` 注入独立 UserDefaults suite，`lanProbeSession` 注入桩会话，不触碰全局单例。

---

### 7.3 T3-3：静默失败接入分类日志（`7a3b79b`）

#### `AppLog` 分类定义 (`AppLog.swift:6-17`)

✅ 三分类 Logger，subsystem 统一为 `"com.fryfrog.hub"`：

| 分类 | category | 覆盖领域 |
|------|----------|----------|
| `AppLog.networking` | `"networking"` | API 请求、认证、偏好同步 |
| `AppLog.image` | `"image"` | 封面下载、磁盘缓存、降采样解码 |
| `AppLog.storage` | `"storage"` | Keychain、UserDefaults、音乐缓存 |

**可过滤性**: `log stream --predicate 'subsystem == "com.fryfrog.hub"'` 可统一捕获三分类，符合要求。

#### 调用面落点统计

| 文件 | 调用次数 | 分类 |
|------|----------|------|
| `MusicCacheService.swift` | 6 | storage |
| `PlayerSettings.swift` | 2 | storage |
| `MediaLibraryService.swift` | 2 | networking |
| `AuthService.swift` | 5 | networking + storage |
| `VideoService.swift` | 4 | networking |
| `ServerImageView.swift` | 6 | image |
| **合计** | **25** | — |

25 处 `AppLog.*` 调用覆盖网络/图片/存储三条链路，均有落点。

#### `try?` 静默保留评估

全项目 `try?` 分布（Top 5 文件）：

| 文件 | 数量 | 静默理由 |
|------|------|----------|
| `ServerImageView.swift` | 8 | 图片加载失败降级为空白占位，不影响核心功能 |
| `SystemVideoPlayerView.swift` | 6 | 系统播放器 AVPlayer 初始化/会话配置，失败时 UI 已有占位 |
| `MpvVideoPlayerView.swift` | 6 | AVAudioSession 配置、进度上报，失败不阻塞播放 |
| `MusicAudioPlayer.swift` | 6 | AVPlayer 会话/通知注册，失败时播放器功能降级 |
| `MusicCacheService.swift` | 5 | 缓存读写/元数据解析，失败时按空缓存处理 |

**结论**: ~55 处 `try?` 均位于非关键路径（UI 占位、缓存、日志、辅助功能），静默保留理由成立。关键路径（如 `MusicService.setStar`、`APIClient.request`）使用 `throws` 传播，未被 `try?` 吞掉。

---

### 7.4 T3-6：MusicService @MainActor 隔离（`5ac3788`）

#### 注解位置 (`MusicService.swift:13`)

✅ `@MainActor` 标注在 class 声明上方（`@Observable` 之前），语义正确：
```swift
@MainActor
@Observable
final class MusicService { ... }
```

#### 调用面隔离一致性

| 调用方 | 隔离域 | 结论 |
|--------|--------|------|
| `MusicView` | SwiftUI View → @MainActor | ✅ |
| `MusicNowPlayingView` | SwiftUI View → @MainActor | ✅ |
| `MusicSongRow` | SwiftUI View → @MainActor | ✅ |
| `MusicAlbumView` | SwiftUI View → @MainActor | ✅ |
| `MusicArtistView` | SwiftUI View → @MainActor | ✅ |
| `MusicPlaylistView` | SwiftUI View → @MainActor | ✅ |
| `PlaylistSongRow` | SwiftUI View → @MainActor | ✅ |
| `CreatePlaylistSheet` | SwiftUI View → @MainActor | ✅ |
| `AddToPlaylistSheet` | SwiftUI View → @MainActor | ✅ |
| `HomeView` | SwiftUI View → @MainActor | ✅ |
| `MusicCacheService.shared` | `@MainActor` (line 14) | ✅ |
| `MusicAudioPlayer.shared` | `@MainActor` (line 6) | ✅ |

**全部 12 个调用方均处于 MainActor 隔离域**，无跨隔离调用，无数据竞态风险。

#### 依赖注入确认

`MusicService` 内部使用 `any APIClientProtocol` 和 `any ServerConnectionProtocol`（`MusicService.swift:18-19`），不再硬编码 `APIClient.shared`，与 T3-1 协议抽象对齐。

---

### 7.5 Phase 3 审查结论

| 任务 | 提交 | 结论 |
|------|------|------|
| T3-1 网络层协议抽象 | `a85e1be` | ✅ **REVIEW_PASS** — 协议 7 项要求完整、6 重载无遗漏、构造注入正确 |
| T3-2 单元测试 | `ef06b2c` | ✅ **REVIEW_PASS** — 15 用例覆盖双失败/无备选/401 豁免/403 不登出等边界 |
| T3-3 分类日志 | `7a3b79b` | ✅ **REVIEW_PASS** — 3 分类 + 25 调用落点 + ~55 try? 静默理由成立 |
| T3-6 @MainActor | `5ac3788` | ✅ **REVIEW_PASS** — 12 调用方均 MainActor 隔离，无跨隔离泄漏 |

**Phase 3 轮次最终裁定: `REVIEW_PASS`**

无需返工。待 Leader 打 `refactor-phase3-pass` Tag 后关闭本轮重构。
