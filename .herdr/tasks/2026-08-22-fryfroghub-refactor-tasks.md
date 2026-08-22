# FryfrogHub 重构任务单 — Leader 分派版

> 生成时间: 2026-08-22 · Leader: Muse Spark (只做 Leader 职责，不直接改代码)  
> 依据: 项目检查报告 + 现场核验（51 Swift文件/13111行/17单例/90处 try?/2处 try!/`ServerImageView.swift:128` 并发隐患）  
> 前置门禁: 非 Herdr 环境，本单为静态任务分解，待 `git init` 后可接入 `mode=do` 闭环

## 分派原则

- 单例保留 `shared` 兼容，新增 `Protocol + 构造注入`，不一次性全量重构
- 巨型文件拆分 = 纯搬运，不改逻辑，每拆一文件编译通过再拆下一文件
- P0 必须先闭环，否则 P1/P2 无法回归

---

## Phase 0 — 基建门禁 (P0, 阻塞项)

| 任务ID | 标题 | 负责人 | 依赖 | 工时 | 文件 |
|---|---|---|---|---|---|
| T0-1 | git 初始化 + .gitignore | Leader/Executor-A | 无 | 0.5h | 仓库根 |
| T0-2 | 清理 `build/` 产物并确认 `project.yml` 生成链路 | Executor-A | T0-1 | 0.5h | `project.yml`, `FryfrogHub.xcodeproj/` |

**验收:**
- `git status` 干净，`build/` `DerivedData` `*.xcarchive` `*.ipa` 已忽略
- `xcodegen generate` 无 warning，`xcodebuild -project FryfrogHub.xcodeproj -scheme FryfrogHub -configuration Release build` 通过
- `.gitignore` 必须包含: `build/`, `DerivedData/`, `*.xcarchive`, `*.ipa`, `.mimocode/node_modules/` 等

---

## Phase 1 — 并发与崩溃隐患 (P0, 最高优)

| 任务ID | 标题 | 负责人 | 依赖 | 工时 | 文件 |
|---|---|---|---|---|---|
| T1-1 | `DispatchSemaphore` in async 替换为 `AsyncSemaphore` | Executor-A | T0 | 1d | `FryfrogHub/Views/Shared/ServerImageView.swift:128,153` |
| T1-2 | `MpvMetalView` try! 降级 + `makeCommandQueue` 空值处理 | Executor-A | T0 | 0.5d | `FryfrogHub/Views/Player/MpvMetalView.swift:38-50` |
| T1-3 | `MpvPlayer` 事件循环 `DispatchSemaphore` 合规性复核 | Executor-A | T1-1 | 0.5h | `FryfrogHub/Views/Player/MpvPlayer.swift:27` |

**T1-1 详情:**
- 现状: `ServerImageView.swift:128` `private let semaphore = DispatchSemaphore(value: 4)` + `ServerImageView.swift:153` `semaphore.wait()` 在 `Task.detached(priority:.utility)` 内阻塞协作线程池，有优先级反转风险
- 目标: 引入 `AsyncSemaphore`（自研 actor 或 `AsyncAlgorithms`），或用 `TaskGroup` + `AsyncStream` 限流 4 并发
- 验收: Instruments Thread State 无 blocking，首页 120 张封面并发加载不丢帧，内存峰值 <400MB 保持不变；单元测试可跑 `loadScaled` 并发 8 任务不死锁
- 禁止: 直接改 `concurrency` 数值，需保留 `maxCacheEntries=120` `maxPixelSize=1200` 语义

**T1-2 详情:**
- 现状: `MpvMetalView.swift:44` `try! device.makeLibrary` + `MpvMetalView.swift:50` `try! makeRenderPipelineState` + `MpvMetalView.swift:39` `fatalError("Metal 不可用")` + `MpvMetalView.swift:42` `device.makeCommandQueue()!`
- 目标: `init(player:frame:)` 改 `throws` 或 `Optional` 工厂，失败时回调 `onError`，SwiftUI 层显示占位 + 提示；`MpvMetalView` 内部 `library/pipeline` 置为 `MTLLibrary?/MTLRenderPipelineState?`，`tick()` 内 guard
- 验收: 模拟 Metal 不可用（如 `MTLCreateSystemDefaultDevice` 返回 nil 的测试替身）不崩溃，UI 提示可观测

---

## Phase 2 — 巨型文件拆分 (P1, 最大工作量)

> 拆分即搬运，零逻辑变更。每 struct 一文件，目录保持 `Views/<Domain>/`

| 任务ID | 标题 | 负责人 | 依赖 | 工时 | 文件 |
|---|---|---|---|---|---|
| T2-1 | `MusicView.swift` 1836行拆 13 structs | Executor-B | T0,T1 | 2d | `FryfrogHub/Views/Music/MusicView.swift:28,430,541,562,582,657,718,763,828,876,926,975,1126,1832` |
| T2-2 | `MpvVideoPlayerView.swift` 1417行拆分 | Executor-B | T0 | 1d | `FryfrogHub/Views/Player/MpvVideoPlayerView.swift` |
| T2-3 | `ProfileView.swift` 965行拆 9 structs | Executor-C | T0 | 1d | `FryfrogHub/Views/Profile/ProfileView.swift` |
| T2-4 | `SeriesDetailView.swift` 911行拆分 | Executor-C | T0 | 0.5d | `FryfrogHub/Views/Home/SeriesDetailView.swift` |
| T2-5 | `LibraryView` / `HomeView` 等 300-600 行文件评估是否跟进拆 | Leader 决策 | T2-1~4 | 0.5d | `FryfrogHub/Views/Library/LibraryView.swift:642` 等 |

**T2-1 拆分清单 (示例):**
```
Views/Music/MusicView.swift              // 保留 MusicView 入口
Views/Music/MusicSongRow.swift           // MusicSongRow:430
Views/Music/MusicAlbumCard.swift         // MusicAlbumCard:541
Views/Music/MusicArtistCard.swift        // MusicArtistCard:562
Views/Music/MusicAlbumView.swift         // MusicAlbumView:582
Views/Music/MusicArtistView.swift        // MusicArtistView:657
Views/Music/MusicPlaylistRow.swift       // MusicPlaylistRow:718
Views/Music/MusicPlaylistView.swift      // MusicPlaylistView:763
Views/Music/PlaylistSongRow.swift        // PlaylistSongRow:828
Views/Music/CreatePlaylistSheet.swift    // CreatePlaylistSheet:876
Views/Music/AddToPlaylistSheet.swift     // AddToPlaylistSheet:926
Views/Music/MusicMiniPlayer.swift        // MusicMiniPlayer:975
Views/Music/MusicNowPlayingView.swift    // MusicNowPlayingView:1126
Views/Music/LyricsLine.swift             // LyricsLine:1832
```
- 验收: `wc -l Views/Music/*.swift` 单文件 <300行，`xcodegen generate` 后编译通过，`xcodebuild` 0 warning，界面行为与拆前一致（Navigation/播放栏不断）
- 风险: `MusicView.swift` 内共享 `@State` 需提升到 `MusicView` 或 `MusicService`，禁止隐式改状态流

---

## Phase 3 — 可测试化 + 日志 + 代码隐患 (P2)

| 任务ID | 标题 | 负责人 | 依赖 | 工时 | 文件 |
|---|---|---|---|---|---|
| T3-1 | `APIClient`/`ServerConnection` 协议抽象 + 构造注入 | Executor-A | T1 | 1d | `FryfrogHub/Networking/APIClient.swift:3` `FryfrogHub/Networking/APIConfig.swift:21` |
| T3-2 | 关键路径单元测试 | Executor-A | T3-1 | 1d | 新增 `Tests/` target |
| T3-3 | 90处 `try?` 接 `os.Logger` 分类日志 | Executor-C | T0 | 0.5d | 全量 `try?` 分布文件 |
| T3-4 | `MusicService.setStar` 消除 6次逐字段拷贝 | Executor-B | T2-1 | 0.5d | `FryfrogHub/Networking/MusicService.swift:113-148` `FryfrogHub/Models/MusicModels.swift` |
| T3-5 | host 校验去重 | Executor-C | T0 | 0.5h | `FryfrogHub/Views/Login/LoginViewModel.swift:87` `FryfrogHub/Networking/APIConfig.swift:127` |

**T3-1 详情:**
- 新增 `APIClientProtocol` `ServerConnectionProtocol`，`AuthService`/`HomeService`/`MusicService` 等 5 个 Service 改 `init(client: APIClientProtocol, server: ServerConnectionProtocol)`，保留 `static let shared` 用默认实例作兼容
- 验收: 业务代码无 `APIClient.shared` 硬编码（除兼容入口），可注入 Mock 客户端

**T3-2 详情:**
- 至少覆盖: `APIClient.requestWithFallback` 内外网切换（`APIClient.swift:54`）、`isConnectionFailure` 判定（`APIClient.swift:173`）、`ServerConnection.probeLAN/refreshActiveMode`（`APIConfig.swift:158-188`）、401/403 handler 注入
- 验收: `xcodebuild test` 通过，覆盖率不要求全量，但上述分支必须命中

**T3-3 详情:**
- 引入 `Logger(subsystem:"com.fryfrog.hub", category:"networking|image|storage")`，`try?` 保留但加 `logger.warning/error`，非关键路径失败可排查
- 验收: Console 可按 category 过滤，线上问题可定位

**T3-4 详情:**
- 在 `MusicModels.swift` 为 `MusicSong`/`MusicAlbum`/`MusicArtist` 增加 `func updating(starred: Bool) -> Self`（或 `withStarred`），`MusicService.swift:124-144` 6处拷贝改为调用
- 验收: 模型新增字段时不再漏改，`setStar` 单测通过

**T3-5 详情:**
- `LoginViewModel.isValid(host:port:)` 复用 `ServerConnection.urlString(for:)` 或抽 `HostValidator`，两处 `host.contains(":")` 补括号逻辑统一
- 验收: IPv6 裸地址 `2409:...` 与 `[2409:...]` 均校验通过，重复代码消除

---

## 角色与门禁

| 角色 | 职责 | 约束 |
|---|---|---|
| Leader (当前) | 任务分解、优先级裁决、最终验收 | 不直接改业务代码 |
| Executor-A | P0 并发/基建 + P2 可测试化 | 只能改任务单内文件，diff 需附验证证据 |
| Executor-B | Music/Player 巨型文件拆分 + setStar 重构 | 纯搬运，禁止改逻辑 |
| Executor-C | Profile/Series 拆分 + 日志 + host去重 | 同上 |
| Reviewer | 只读审查，追加评审单 | 不改源码，`REVIEW_PASS`/`REVIEW_CHANGES_REQUIRED` 需带文件:行证据 |

**门禁:**
- 每 Phase 结束需 Reviewer `REVIEW_PASS` 才进入下一 Phase
- `max_rework=2`，超限由 Leader 接管
- 任何 Phase 引入新依赖（如 `AsyncAlgorithms`）需 Leader 审批

## 里程碑

- M1 (T0+T1): 0.5d + 1.5d = 2d，产出：无崩溃、可并发、无阻塞
- M2 (T2): 4.5d，可选拆 2 人并行压缩至 2.5d
- M3 (T3): 3.5d
- **合计 6-10 人日**，单人串行约 10d，三人并行约 5d

## 下一步 (Leader 指令)

1. 确认本任务单是否按此分派（或调整 Executor 人选）
2. 执行 `T0-1` git 初始化（Leader 授权后由 Executor-A 执行）
3. 进入 `mode=do` 闭环，Executor-A 先领 T1-1
