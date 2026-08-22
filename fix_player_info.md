# 播放器信息面板优化

## 改动内容

### 1. MpvPlayer.swift
- 添加 `dynamicRange` 字段到 `PlaybackInfo` 结构体
- 添加 `detectDynamicRange()` 方法，根据 `video-params/transfer` 属性检测动态范围：
  - `smpte2084` → HDR10
  - `arib-std-b67` → HLG
  - 其他 → SDR
- 更新 `fetchPlaybackInfo()` 调用 `detectDynamicRange()`

### 2. MpvVideoPlayerView.swift
- 重写 `infoMenuPanel`，只保留用户需要的信息：
  - 播放类型（直接播放）
  - 缓冲时长
  - 视频：分辨率、编码器、动态范围、帧率
  - 音频：编码器、声道、采样率
  - 媒体源：封装容器
- 删除不需要的字段：像素格式、解码方式、码率、传输协议、字幕轨
- 添加 `playTypeText` 和 `dynamicRangeText` 属性
- 删除 `bitrateText` 和 `decodeText` 方法（不再使用）

## 效果
信息面板更简洁，只显示关键参数，减少不必要的信息展示。
