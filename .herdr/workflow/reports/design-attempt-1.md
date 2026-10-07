# 设计阶段完成 — 灵动岛 Live Activity

已完成 `.herdr/plans/2026-08-22-live-activity-design.md:1` 设计，结论 **accepted**。

**调研**：`MusicAudioPlayer.swift:8` AVPlayer + `MPNowPlayingInfoCenter:382` 已支持后台音频，缺 ActivityKit。

**方案**：新增 `MusicLiveActivityAttributes` + `MusicLiveActivityService` 单例，Widget Extension `FryfrogHubLiveActivity` 承载锁屏与灵动岛三形态（Compact/Expanded/Minimal），主 App `project.yml` 追加 `NSSupportsLiveActivities`，`MusicAudioPlayer` 在 `play:96/toggle:143/seek:195/timeObserver:364/next:256/previous:276/stop:301` 7 处同步 `start/update/end`，`areActivitiesEnabled` 守卫 + `#available(iOS 16.1, *)`，1s 节流更新，deep link 先行、AppIntent 二期。

**验证**：iPhone 14 Pro 真机灵动岛 + 锁屏 Live Activity 与 `currentSong/isPlaying/position` 一致，控制回主 App 生效；无权限/低版本不崩溃；`xcodebuild build` 0 warning。

请进入 implement 阶段。
