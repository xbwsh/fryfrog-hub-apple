# Implement 完成报告 — 移除灵动岛（attempt 2）

**按 rework 指令执行**：移除 Live Activity，保留系统后台播放。

## 变更
- 删除 `FryfrogHubLiveActivity/` 扩展目录（Bundle/Widget/Views）
- 删除 `FryfrogHub/Models/MusicLiveActivityAttributes.swift`、`FryfrogHub/Services/MusicLiveActivityService.swift`
- 回退 `FryfrogHub/Services/MusicAudioPlayer.swift:8` 移除 12 处 `MusicLiveActivityService` 调用与 `handleLiveActivityURL`，保留：
  - `AVAudioSession.sharedInstance().setCategory(.playback, mixWithOthers)` 延迟激活
  - `MPNowPlayingInfoCenter.default().nowPlayingInfo` 完整（title/artist/album/duration/position/rate/artwork via AuthImageLoader）
  - `MPRemoteCommandCenter.shared().play/pause/nextTrack/previousTrack`
  - `UIBackgroundModes audio` + 0.5s timeObserver 驱动 position
- 回退 `FryfrogHub/App/FryfrogHubApp.swift:18` 移除 `.onOpenURL { MusicLiveActivityService }`
- 回退 `project.yml:53` 移除 `FryfrogHubLiveActivity` target、`NSSupportsLiveActivities`、`CFBundleURLTypes(fryfrog)`、dependency
- `FryfrogHub/Resources/Info.plist:39` 同步移除 NSSupportsLiveActivities/CFBundleURLTypes，保留 UIBackgroundModes audio
- xcodegen generate → project.pbxproj 无 LiveActivity 引用，stale .o 清理

## 验证
- `xcodebuild -scheme FryfrogHub -destination generic/platform=iOS build` **BUILD SUCCEEDED**（notes 显示 Removed stale MusicLiveActivity*.o & PlugIns）
- grep 验证无 ActivityKit 残留：`grep -r MusicLiveActivity FryfrogHub` 空
- 系统后台播放链路：AVAudioSession + MPNowPlayingInfoCenter + MPRemoteCommandCenter 全保留，锁屏/控制中心/耳机线控仍可用，无需灵动岛。
