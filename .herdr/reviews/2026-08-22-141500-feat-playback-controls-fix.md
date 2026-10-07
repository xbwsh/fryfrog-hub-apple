# Herdr 多 Agent 评审单

> 本文档是本轮评审的唯一持久事实源。所有参与 Agent 只能在文件末尾按轮次追加；
> 不得删除、覆盖、重排既有内容。纠错请追加新轮次说明。

## 基线

- 评审 ID：`2026-08-22-141500-feat-playback-controls-fix`
- 目标：`feat/playback-controls-fix` 播放页控件唤起卡顿修复（T4-1 手势仲裁 + T4-2 渲染让路）
- 仓库：`fryfrog-hub-apple`
- 分支：`feat/playback-controls-fix`（基线 `refactor-phase3-pass` = 82485a5）
- HEAD：`5a099d3` docs: playback-controls-fix 交付清单（file:line 证据）
- 创建时间：`2026-08-22 14:15:00 +0800`
- Leader：`opencode`（w9:p4, Herdr leader）
- 参与 Agent：`opencode (leader), claude (reviewer)`
- 审查前工作树：`clean`（`git status` 无变更，`git diff HEAD~3..HEAD --stat` 4 files changed, 71 insertions(+), 7 deletions(-)）
- 审查区间：`refactor-phase3-pass..HEAD = 48658da, 810bedb, 5a099d3`（3 commits）
- 审查前 diff 摘要：
  ```
  .herdr/modified/2026-08-22-playback-controls-fix.md   | 31 ++++++++++++++++++++
  FryfrogHub/Views/Player/MpvMetalView.swift         |  7 +++++
  FryfrogHub/Views/Player/MpvMetalViewContainer.swift |  7 ++++-
  FryfrogHub/Views/Player/MpvVideoPlayerView.swift   | 33 ++++++++++++++++++----
  ```
- 交付自证：Release 构建 0 warning；`xcodebuild test` Simulator `1DE872C2` 15/15 TEST SUCCEEDED
- 通信冒烟：`2026-08-22 14:12:40 PING-1787379198-HERDR-TEST` → `claude` PONG 已验证双向直连（`w9:p4`↔`w9:p5`）

---

## 轮次 R1：首轮审查（claude/reviewer）

- 作者：claude
- 角色：reviewer
- 时间：2026-08-22 14:20 +0800
- 上一轮：无（基线后首轮）
- 审查区间：`refactor-phase3-pass..HEAD`（48658da, 810bedb, 5a099d3），审查时工作树 clean；全部行号以 HEAD 5a099d3 为准

### 结论

**REVIEW_PASS（非阻塞放行：0 × P1/P2，3 × P3，2 × P4）。**
未发现阻塞合并的正确性缺陷。核心机制逐项核实通过：

- **T4-1 时间戳自判正确**：
  - `CACurrentMediaTime()`（MpvVideoPlayerView.swift:377）为单调时钟，无墙钟跳变/回拨风险，选型优于 `Date`。
  - 回调均在主线程（SwiftUI 手势回调），无 Timer/Task 延迟链路 → 无并发与线程切换问题。
  - `@State lastTapAt`（MpvVideoPlayerView.swift:54）由 SwiftUI 外部存储支撑，body 重算与结构体重建不丢值；仅视图身份销毁时复位——复位即语义正确的场景。写入时机在手势回调（非 view update 期间），安全。首击的 `lastTapAt` 写入总与 `controlsVisible`/`isPlaying` 写入同帧合并失效，无额外渲染代价。
  - 三击场景：二击置 `lastTapAt = 0`（MpvVideoPlayerView.swift:380），三击距 0 恒 > 0.3s 判为新单击，不会拆成两组双击，与注释一致。
  - 手势边界：拖动走 `simultaneousGesture(adjustGesture)`（minimumDistance:10，:279），长按 sequenced 路径独立（:137-138）；快速点按时长按因未满 0.5s 自然失败、Tap 正常触发，单点 Tap 不吞没二者。
- **T4-2 切换路径安全**：
  - 调用点全在主线程（makeUIView/updateUIView）；`displayLink?.preferredFramesPerSecond`（MpvMetalView.swift:125）可选链使占位 UIView 路径、startRendering 前调用均为安全空操作。
  - makeUIView 内先 `startRendering()` 再 `setControlsVisible(...)`（MpvMetalViewContainer.swift:20-21），顺序符合"需在 startRendering 之后生效"的前置注释。
  - 两处容器调用点（MpvVideoPlayerView.swift:68,73）透传一致，分支重建（videoSize 就绪前后）经 makeUIView 重新初始化，无缝接。
  - `updateUIView` 对占位视图 `(view as? MpvMetalView)?` 类型安全跳过（MpvMetalViewContainer.swift:33）。
- **API 兼容性与语义准确**：`preferredFramesPerSecond` iOS 10+ 可用（兼容面宽于 iOS 15+ 的 `preferredFrameRateRange`）；`= 0` 表示恢复默认最大帧率，与 CADisplayLink 官方语义一致；30 在 ProMotion 支持档位内。
- **方案取舍合理**：降帧（方案二）相对后台渲染（方案一）改动面小、可逆，直接压缩控件动画期间主线程"软渲 + 纹理上传 + 提交"负载，无优先级反转风险；固有代价是控件显示期视频上限 30fps（见 F-002/F-003，真机确认观感即可）。

### 证据

| 问题 ID | 严重度 | 文件与行号 | 证据及影响 |
|---|---|---|---|
| F-001 | P3 | FryfrogHub/Views/Player/MpvVideoPlayerView.swift:127-129, 363-370, 376-386 | 双击副作用描述以偏概全。"双击暂停且控件可见"仅在初态控件**隐藏**时成立（首击 showControls → 二击暂停，onChange 取消自动隐藏，控件留存）；初态控件**可见**时，首击 `toggleControls()` 已隐藏控件（:364-366），二击 `togglePlay()` 暂停，终态为"暂停且控件隐藏"，与注释及交付单宣称的主流行为相反。影响：轻微 UX 状态依赖不一致 + 注释失实。建议修正注释表述，或在双击改判时记录并回滚首击的控件翻转。非阻塞（作者已申报接受该副作用，但申报理由仅覆盖半数初态）。 |
| F-002 | P3 | FryfrogHub/Views/Player/MpvVideoPlayerView.swift:33, 394-402; FryfrogHub/Views/Player/MpvMetalViewContainer.swift:21; FryfrogHub/Views/Player/MpvMetalView.swift:124-126 | 降帧窗口宽于设计意图。`controlsVisible` 初值 `true`（:33）→ makeUIView 即设 30fps（Container:21），启动播放至首次自动隐藏（约 4s，:397-401）期间渲染恒为 30fps，而其中并无 UI 动画在跑（淡入仅 0.15s）。影响：60fps 源内容开场平滑度无谓受损。建议后续改为仅在过渡动画窗口内门控降帧。非阻塞。 |
| F-003 | P3 | FryfrogHub/Views/Player/MpvMetalView.swift:121-126; .herdr/modified/2026-08-22-playback-controls-fix.md:23 | 方案二固有代价未申报：>30fps 源（如 60fps）在控件显示期间必然隔帧抽取产生抖动；交付单待验项仅列"淡入无掉帧"（md:23），未列高帧率源抽帧项。建议补入真机验收清单一并复核。缓解事实：主流 24/30fps 片源不受影响；tick 按 `needsRedraw` 事件驱动（MpvMetalView.swift:172-180）、暂停零开销。非阻塞。 |
| F-004 | P4 | .herdr/modified/2026-08-22-playback-controls-fix.md:13-15,20 对照 HEAD 5a099d3 | 交付单 file:line 漂移：T4-2 引用 `MpvMetalView.swift:96-101` 实际指向 `logFailure`，`setControlsVisible` 实位于 121-126（含注释）；T4-1 引用 52-53 / 119-130 / 368-384，实际为 53-54 / 121-131 / 372-386（±2~4 行）。评审定位不受阻（本表均已按 HEAD 校正），建议后续交付前以最终 HEAD 重校行号。 |
| F-005 | P4 | FryfrogHubTests/APIClientFallbackTests.swift; FryfrogHubTests/ServerConnectionTests.swift | 15/15 用例均为网络层回归（API fallback、ServerConnection），不含手势窗口判定与降帧同步分支。建议将 `handlePlayAreaTap` 的窗口判定（MpvVideoPlayerView.swift:376-386）提取为纯函数 `(now, lastTapAt) -> (action, next)` 补单元测试；最有价值用例：≤0.3s 边界判双击、>0.3s 判单击、三击重置后不连锁。非阻塞。 |

核实通过项备查（不计问题）：单调时钟选型、主线程约束、nil 安全可选链、makeUIView 调用顺序、双调用点一致性、updateUIView 类型安全跳过、iOS 版本兼容与 `0` 语义、三击防误判逻辑与注释一致、`@State` 生命周期语义、"淡入无掉帧"已按约定标记真机待验（交付单 md:23 ✓）。

### 确认/驳回

本轮为首轮，无需确认旧问题。新增问题：F-001、F-002、F-003（P3）；F-004、F-005（P4）。

观察备案（非本区间引入、不计数）：长按 2x 松手时 TapGesture 无时长上限可能额外触发一次 `handlePlayAreaTap` 造成控件翻转——该行为与基线 `exclusively(before:)` 的单击兜底路径等价，属既有交互，留待真机复验时顺带确认即可。

### 交接

- 下一 Agent：opencode (leader)
- 交接定位：.herdr/reviews/2026-08-22-141500-feat-playback-controls-fix.md#R1
- 待处理问题 ID：F-001, F-002, F-003, F-004, F-005（均非阻塞；F-003 含真机待验项）
- 建议：可合并；P3/P4 可折入下一迭代或随真机验收闭环

---

## 最终裁决 R2

- 裁决者：opencode (leader, w9:p4)
- 时间：2026-08-22 14:25 +0800
- 裁决：`REVIEW_PASS`
- 有效问题 ID：`无`（R1 的 F-001~F-005 均为 P3/P4 非阻塞，未纳入有效阻塞集；观察备案不计数）
- 最终结论：同意合并至基线分支。R1 的正确性核实结论予以确认，未发现 P1/P2。

### Leader 独立抽查

- 已重读：`MpvVideoPlayerView.swift:53-54,121-131,363-386,33,394-402`、`MpvMetalView.swift:109-126,172-180`、`MpvMetalViewContainer.swift:5-34`、` .herdr/modified/2026-08-22-playback-controls-fix.md`、本次 `git diff refactor-phase3-pass..HEAD`
- 对 R1 问题逐项复核：
  | 问题 ID | Leader 判定 | 理由 |
  |---|---|---|
  | F-001 | 确认，P3 非阻塞 | 复现逻辑与 claude 一致：初态 visible 时双击终态 hidden，注释「双击暂停且控件可见」仅半覆盖。同意「轻微 UX 状态依赖 + 注释失实」，不阻塞；建议下迭代将注释改为「双击暂停（首击的控件翻转已生效，终态取决于初态）」或在双击分支记录首击前 `controlsVisible` 并回滚。 |
  | F-002 | 确认，P3 非阻塞 | `controlsVisible=true` 初值导致开场 4s 恒 30fps 确属浪费。当前不阻塞，但同意 R1 建议：后续迭代将降帧门控收窄至动画窗口（如 `withAnimation` 期间或 `controlsVisible` 变化后 0.3s 内），而非全程 `controlsVisible` 绑定。 |
  | F-003 | 确认，P3 非阻塞 | 60fps 源在控件显示期抽帧抖动属方案二固有代价，交付单 md:23 仅列「淡入无掉帧」确有遗漏。已标记真机待验，补充待验项「60fps 片源在控件常显时是否可接受抖动」即可闭环。主流 24/30fps 不受影响，`needsRedraw` 驱动已降低空转开销，方案取舍成立。 |
  | F-004 | 确认，P4 非阻塞 | file:line 漂移 ±2~4 行属实，已在 R1 按 HEAD 校正，不影响可追溯性。下次交付前以 `git rev-parse HEAD` 行号为准重校即可。 |
  | F-005 | 确认，P4 非阻塞 | 15/15 确为网络层回归，确缺手势/渲染单测。同意 R1 建议的纯函数抽取方向，非本迭代阻塞项。 |
- 观察备案：长按 2x 松手触发 Tap 的既有行为与基线等价，确认不计数，留真机顺带观察。

### 对提审人预留两点的回应

1. **体感验收需真机**：`handlePlayAreaTap()` 时间戳逻辑 `MpvVideoPlayerView.swift:376-386` 已静态核对通过——`CACurrentMediaTime()` 单调、`@State` 生命周期安全、三击 `lastTapAt=0` 防连锁、手势边界 `simultaneousGesture` 不互吞，均符合预期；「单击 <50ms 唤起」已由「无延迟立即 toggleControls」结构保证，无 300ms 阻塞路径。`setControlsVisible` 主线程可选链与调用顺序亦已核对通过。余下「淡入无掉帧」确需真机 Instruments 复核，已纳入 F-003 待验。

2. **T4-2 方案二批准**：同意交付单对方案二的选型结论。`renderFrame` 后台化需引入 `frameBuffer`/`frameTexture` 跨线程锁与拷贝同步，改动面与回归风险显著高于「30↔0 帧率切换」；后者在主线程单点切换、可逆、低侵入，已足以让路 0.15s 淡入动画。无需按返修切方案一；当前 F-002/F-003 的窗口收窄与待验补充已覆盖方案二的残余代价。

### 合并门禁

- 工作树对比：审查前后仅新增 `.herdr/reviews/2026-08-22-141500-feat-playback-controls-fix.md`（本文件），无其他工作树写入，符合 `review/SKILL.md:9` 要求
- 构建与测试：采信交付单 Release 0 warning 与 1DE872C2 15/15；本审查未引入需重跑的源码变更
- 返修：0 阻塞，无需返修

### 交接

- 评审单路径：`.herdr/reviews/2026-08-22-141500-feat-playback-controls-fix.md`
- 最终裁决：`REVIEW_PASS`（0 P1/P2，可合并；F-001~F-005 转后续迭代/真机闭环）
