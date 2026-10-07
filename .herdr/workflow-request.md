我需要移除灵动岛功能，音乐后台播放使用系统组件就行

- 移除 FryfrogHubLiveActivity Widget Extension 及所有 Live Activity 相关代码（MusicLiveActivityAttributes、MusicLiveActivityService、AppIntent/DeepLink）
- 移除 project.yml 中 NSSupportsLiveActivities、CFBundleURLTypes(fryfrog)、FryfrogHubLiveActivity target 及其依赖
- 回退 MusicAudioPlayer 与 FryfrogHubApp 中所有 MusicLiveActivityService 同步与 handleLiveActivityURL/onOpenURL 逻辑
- 保留系统级后台播放：AVAudioSession(.playback)、UIBackgroundModes audio、MPNowPlayingInfoCenter、MPRemoteCommandCenter（锁屏/控制中心/耳机线控）保持不变
- 清理后重新生成 Xcode 工程并验证 xcodebuild build 0 warning
