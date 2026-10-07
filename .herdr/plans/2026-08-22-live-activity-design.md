# Live Activity / 灵动岛 设计方案 — Music 后台播放

> 关联需求：`我发现我的软件退出到后台可以播放音乐，但是我发现它没有接入苹果的灵动岛`
> 目标：在用户切后台后，于 灵动岛（Dynamic Island）与锁屏 Live Activity 实时展示当前曲目、进度、播放状态，并提供播放/暂停、上一首/下一首 控制。
> 规范：iOS 16.1+ ActivityKit，iPhone 14 Pro+ 灵动岛，iOS 17.0 deploymentTarget 已满足。

## 1. 现状调研

- **MusicAudioPlayer.swift:7** `@MainActor @Observable` 单例 `shared`，`AVPlayer` + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` 已打通后台 `audio`（`Info.plist: UIBackgroundModes audio`）与锁屏/控制中心。
- **生命周期**：`play(_:queue:):96` 创建 `AVPlayer(url:)` → `play()` → `configureNowPlaying:382`；`pauseWithFade:175` 渐隐、`handleTrackEnded:224` / `playNext:256` / `playPrevious:276` 切歌；`position` 由 `addPeriodicTimeObserver 0.5s:364` 驱动。
- **未接入**：无 `ActivityKit` 依赖，无 `NSSupportsLiveActivities` 标记，无 Widget Extension，无 Live Activity 状态同步。

## 2. 目标行为

| 场景 | 灵动岛 / Live Activity 表现 |
|---|---|
| 播放时切后台 | 灵动岛左侧封面+标题滚动，右侧播放动画；展开显示封面、标题/歌手、进度条、播放/暂停、上一首/下一首 |
| 暂停 | 灵动岛图标仍驻留，状态置灰，进度冻结；Live Activity `isPlaying=false` |
| 切歌 / 自动下一首 | Live Activity 立即 `update` 新曲目，`staleDate=nil` |
| 停止 / 队列播完 | `end` Activity，`dismissalPolicy=.immediate` |
| 覆盖安装 / 权限关闭 | 无 Activity，不崩溃，`areActivitiesEnabled` 守卫 |

## 3. 架构设计

### 3.1 新增模块

```
FryfrogHub/Services/MusicLiveActivityService.swift      // 单例，管理 Activity 生命周期
FryfrogHub/Models/MusicLiveActivityAttributes.swift     // ActivityAttributes 定义
FryfrogHubLiveActivity/                               // 新 Widget Extension Target
  ├─ FryfrogHubLiveActivityBundle.swift
  ├─ MusicLiveActivityWidget.swift                    // ActivityConfiguration
  ├─ Views/LockScreenLiveActivityView.swift
  └─ Views/DynamicIslandViews.swift                   // Compact/Expanded/Minimal
```

### 3.2 ActivityAttributes

```swift
struct MusicLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var artist: String
    var album: String?
    var artworkURL: String?      // 封面 URL，锁屏异步加载
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var updatedAt: Date
  }
  var songId: Int64
}
```

- `ContentState` 仅 Codable+Hashable，`songId` 用作去重键。
- 封面不直接传 `UIImage`（过大），传 URL，Widget 侧经 `AuthImageLoader` 或 `AsyncImage` 加载。

### 3.3 交互模型

- **App 内控制**：`MusicAudioPlayer` 现有 `toggle()/playNext()/playPrevious()` 保持主路径，Live Activity 侧通过 `AppIntent` 或 `openURL` 回调到主 App 再执行。
- **Widget 侧按钮**：`Intent` 方案（iOS 16.1+）：`TogglePlayIntent` / `NextTrackIntent` / `PreviousTrackIntent` 为 `AppIntent`，在 Widget 按钮 `Button(intent:)` 中触发，主 App 的 `MusicAudioPlayer.shared` 执行。
- 简化首版可用 `widgetURL` deep link：`fryfrog://music/toggle` 等，`onOpenURL` 派发，避免额外 Intent 权限；二期再切 AppIntent 以支持不启动 App 的后台执行。

### 3.4 生命周期同步点

| 触发点 | MusicAudioPlayer 调用 | LiveActivity 动作 |
|---|---|---|
| `play(_:queue:):96` | `MusicLiveActivityService.shared.startOrUpdate(song:position:isPlaying)` | `Activity.request` 若无活跃 Activity，否则 `update` |
| `toggle/playCurrent/pause:143` | 同上 `update` `isPlaying` | `activity.update(ActivityContent(state:..., staleDate:nil))` |
| `seek(to:195)` | `update` position | 同上 |
| `timeObserver 0.5s:364` | 节流后 `update` position（1s 一次，避免高频） | 同上，`updatedAt=Date()` 供 Widget 侧 `TimelineView` 动画 |
| `handleTrackEnded/playNext/playPrevious` | `startOrUpdate` 新 song | `update` 或 `end`+`request` 新 |
| `stop:301` | `end` | `activity.end(dismissalPolicy:.immediate)` |
| `AVAudioSession.interruption:64` | 同步 `isPlaying` | `update` 状态 |

- 采用 `ActivityAuthorizationInfo().areActivitiesEnabled` 守卫，关闭则静默跳过。
- 仅保留一个活跃 Activity：`Activity<MusicLiveActivityAttributes>.activities.first` 去重。

## 4. 工程配置

### 4.1 project.yml

- 新增 target `FryfrogHubLiveActivity`：`type: app-extension`，`platform: iOS`，`deploymentTarget: 17.0`，`sources: FryfrogHubLiveActivity`，`dependencies: [target: FryfrogHub]`（或共享 Models）。
- 主 App `info.properties` 追加 `NSSupportsLiveActivities: true`。
- Extension `info.properties` 追加 `NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }`（XcodeGen 自动生成，可显式声明）。
- Extension BundleId：`com.fryfrog.hub.liveactivity`，`DEVELOPMENT_TEAM` 同主 App。

### 4.2 Info.plist

- 主 App：`NSSupportsLiveActivities = YES`（project.yml 中声明）。
- 无需额外 `NSLiveActivityUsageDescription`（系统自动）。

### 4.3 依赖与版本

- `import ActivityKit`，`@available(iOS 16.1, *)` 全链路守卫，iOS 17.0 部署目标已满足，低版本分支直接 `return`。
- `WidgetKit` 仅 Extension 侧引入。

## 5. UI 设计

### 5.1 锁屏 Live Activity

- 封面 56pt 圆角 8，标题/歌手单行截断，进度条 `ProgressView` + `Text(time)`，控制栏 `上一首 | 播放/暂停 | 下一首` 44pt 击区。
- 背景 `.activityBackgroundTint(.black)`，深色适配。

### 5.2 灵动岛

- **CompactLeading**：封面 24pt 圆角
- **CompactTrailing**：播放指示（波形或 `isPlaying` 脉动）+ 标题跑马灯（简化为单行）
- **Minimal**：音符图标
- **Expanded**：上区封面+信息，下区进度+控制，与锁屏一致但横向布局，高度按 Apple 规范 `≈ 96pt`。

## 6. 时序与节流

- `position` 更新节流 1s（`timeObserver` 0.5s 触发，但 LiveActivity 1s 合并一次 `update`，避免每秒 2 次 IPC）。
- `isPlaying` / `song` 变更立即 `update`。
- `staleDate` 置 `nil`，不自动过期；`relevanceScore` 按最新 `Date()` 递增。
- 后台切前台无需特殊处理，Activity 随系统常驻；App 杀死时系统自动结束。

## 7. 测试计划

- **单元**：`MusicLiveActivityService` Mock `Activity` 行为，验证 `start → update → end` 状态机，`areActivitiesEnabled=false` 不发起请求。
- **UI**：Xcode Previews 为 Widget 提供 `MusicLiveActivityAttributes.ContentState` Mock 数据，验证三种 Dynamic Island 形态。
- **真机**：iPhone 14 Pro/15 Pro 切后台，验证灵动岛出现、展开/收起、按钮回主 App 生效、锁屏 Live Activity 同步；模拟器验证 Live Activity 列表（Dynamic Island 需真机）。

## 8. 风险与回退

- **无 Extension 权限/用户关闭 Live Activities**：守卫直接跳过，不影响 `MPNowPlayingInfoCenter` 现有后台播放。
- **旧系统**：`#available` 守卫，iOS <16.1 直接 `return`。
- **多 Activity 残留**：启动时清理 `Activity.activities.filter { $0.id == ... }` 旧实例，仅保留最新。

## 9. 拆分与排期

| 步骤 | 文件 | 负责人 |
|---|---|---|
| 9.1 | `MusicLiveActivityAttributes.swift` + `MusicLiveActivityService.swift` | implementer |
| 9.2 | `project.yml` + `Info.plist` + Extension Target 骨架 | implementer |
| 9.3 | `MusicLiveActivityWidget.swift` + 锁屏/灵动岛 Views | implementer |
| 9.4 | `MusicAudioPlayer.swift` 埋点（7 处调用） | implementer |
| 9.5 | 预览与真机联调 | implementer + leader |

## 10. 验收标准

- 后台播放时灵动岛与锁屏 Live Activity 均出现，信息与 App 内 `currentSong/isPlaying/position` 一致。
- 灵动岛展开可操作上一首/下一首/播放暂停，且与主 App 状态双向同步。
- 无 Live Activity 权限或 iOS <16.1 时不崩溃，现有后台音频与 `MPRemoteCommandCenter` 保持不变。
- `xcodebuild build` 0 warning，`xcodebuild test` 15/15 通过（新增 Service 单测覆盖）。
