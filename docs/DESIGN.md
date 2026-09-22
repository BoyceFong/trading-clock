# TradingClock — 设计文档

架构与设计决策。用户使用说明见根目录 [README](../README.md)。

- macOS 26（Tahoe）+ Xcode 26 构建，Swift 6.2 / SwiftUI + AppKit，Liquid Glass（`NSGlassEffectView`），零第三方依赖
- SwiftPM 包 + `Scripts/build.sh` 组装 .app（无 .xcodeproj），工程形态与同作者 economic-calendar widget 同构（该工程已趟平 Liquid Glass、登录项、无边框面板的坑）
- 无 Dock 图标（`LSUIElement`），Nonactivating Panel（点击不抢焦点），菜单栏常驻

## 目标与非目标

**目标**：5 分钟价格行为交易的桌面节拍器——精确对时、收盘倒计时、临界闪光、不遮盘面、随手可及。

**非目标**：交易信号、行情接入、声音/系统通知、多周期支持（产品固定 5 分钟边界）、跨平台。

## 工程布局

```
Sources/TradingClock/
  main.swift           # NSApplication 装配 + CLI（--glow-preview）
  App/                 # AppDelegate、ClockPanel、AppModel、AppActions、GlowPreview
  Core/                # ClockEngine（时间驱动）、CandleClock（K线相位）、Settings
  Services/            # HotKeyService、LoginItemService、StatusItemController、GlassFrostGuard
  UI/                  # RootView、FlipDigitView、FlashOverlayView、EdgeGlowMask、Theme…
Support/Info.plist     # LSUIElement、LSMinimumSystemVersion 26.0
Scripts/build.sh       # swift build → 组装 dist/*.app → ad-hoc 签名 → --install
Sources/TradingClock/Resources/{en,zh-Hans}.lproj/Localizable.strings
```

构建要点：xcode-select 默认指向 CommandLine Tools（SDK 15.5），Liquid Glass 需要 Xcode 26 SDK，故 `build.sh` 内固定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，不需要切换 xcode-select。

## 核心子系统

### 1. 时间驱动 ClockEngine —— 零漂移

**问题**：`Timer(interval: 1)` 自由累加会漂移；翻页钟一旦偏秒，观感立刻崩。

**方案**：每拍从 `Date()` 算出「下一个整秒边界」单次触发；触发后**一律从当前 `Date()` 重算全部显示**——晚触发自纠，永不累积。`tolerance = 0`（精确度优先）；装进 `.common` runloop mode（菜单打开时照常走秒）。

**配套**：监听 `NSWorkspace.didWakeNotification`（睡眠唤醒补跳）、`NSSystemClockDidChange`、`NSSystemTimeZoneDidChange`，即时 `resync()` 重建调度。

### 2. K 线相位机 CandleClock

收盘点 = 本机时钟整 5 分（`minute % 5 == 0 && second == 0`）。快照给出：

- `secondsToClose ∈ 1...300`（新一根开盘即 5:00）
- 剩余 **30/29/28 秒 → 黄闪 ×3**；剩余 **5..1 秒 → 红闪 ×5**；每秒 1 脉冲

可测性：`TC_CANDLE_LEN_SECONDS`（默认 300）压缩周期，30 秒即可完整演练黄/红节奏。边界条件已单测（跨 :05/:10 两处收盘点全过）。

### 3. 翻页机构 FlipDigitView —— 真实 Solari 动作

**问题**：两段式折叠（上半落下 + 下半再落）会露馅成「数字滑下来」，相位切换处跳变。

**方案**：**单页 180° 真翻转**——一张半卡绕中缝向前落下，正面 = 旧数字上半，背面 = 新数字下半（预翻转 180° 保证落定后正读）。静态上半露出新数字上半（随落页揭开），静态下半保留旧数字下半（落定时盖住）。这与真实翻页钟的机械动作同构。

**运动曲线**（四段首尾速度连续，总时长 ≈0.32s，`Theme.flipTip/Fall/Whip/Land`）：

| 段 | 角度 | 力学 |
|---|---|---|
| 离合慢起 | 0→~60° | 重力力矩刚占上风，耗时近半 |
| 加速下坠 | 60→126° | 摆落加速 |
| 甩过垂直 | 126→171° | 全程最高速 |
| 砸停 | 171→180° | 硬着陆 + 极轻微回弹（Spring bounce 0.12） |

**帧率与清晰度**：`KeyframeAnimator` 按显示刷新率（60–120fps）插值整条曲线；卡片字面**预渲染 4× 位图**（`FaceRaster`/`ImageRenderer` 缓存）——3D 旋转是纯 GPU 位图变换，文字不每帧重排版，不糊不掉帧。

**复位不可见**：`from`/`to` 交换与 animator trigger 递增同帧完成，动画重启帧画的仍是旧数字，复位永不闪跳。

### 4. 警示光晕 EdgeGlowMask —— 第一性原理

**问题**：「描边 + 模糊」堆光晕永远调不匀——上下粗、左右细。根因是方法本身：宽描边在圆角处内缘曲率半径被钳成 0（几何失真）；模糊外溢被窗口圆角裁掉一半能量；「条」的视觉重量又与边长成正比（726pt 的上下边 vs 317pt 的侧边），且黄/红光叠在白色 K 线图上天然低对比。

**方案**：发光强度只由**该像素到窗口圆角矩形边缘的真实距离 t**（精确 SDF）决定：

```
f(t) = wash + peak·e^(−t/λ) + slope·max(0, 1 − t/H)
     = 0.05 + 0.13·e^(−t/λ) + 0.08·(1 − t/H)     （λ = 0.085·min(边长)，H = min(边长)/2）
```

「整圈等亮」在此定义下是恒等式而非调参结果。逐像素栅格化为白色 alpha 蒙版（`EdgeGlowMask.image`），绘制时着色——几何与颜色解耦。高亮环为矢量恒宽双线：彩色 3.5pt + **白芯 1.3pt**（白底图表可读性）。

**验证**（`--glow-preview`，复用生产代码路径）：上/下/左/右/两角同距（10pt）采样 α 偏差 ≤1/255（`UNIFORMITY: PASS`）；黑/白四象限对照图见 README。

### 5. Liquid Glass 与 GlassFrostGuard

**材质**：AppKit `NSGlassEffectView`（`style = .clear`，`cornerRadius = 26`），内容按 WWDC25-310 要求经 `contentView` 嵌入（勿把玻璃当 sibling 垫底）。系统「降低透明度」自动降级不透明（`TC_GLASS_MODE` 可强制 material/solid 调试）。

**失焦磨砂问题**：运行时探测确认 `NSGlassEffectView` 内部走 `-_windowChangedKeyState` → `-_subduedState` / `-_scrimState` 私有链路，窗口失焦即自动起雾；macOS 26 **无公开开关**（`effectIsInteractive` 是 27 的 API）。

**方案**：`GlassFrostGuard` 在启动时用 `method_setImplementation` 把这三个钩子替换为 no-op，玻璃恒定保持聚焦时的全透明处理。

**⚠️ 风险记录**：这是私有 API 钩子，未来 OS 更新可能改名或移除（届时该 hack 失效、失焦恢复起雾，但不影响其余功能）。缓解：只在运行时确认 selector 存在时才替换，找不到即静默跳过。

### 6. 窗口 ClockPanel

`NSPanel`：`[.borderless, .nonactivatingPanel, .resizable]` + 透明背景 + `level = .floating` + `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`（全 Space、全屏交易软件之上、不抢焦点、不进 ⌘\` 循环）。

- **拖动**：`DragHostingView.mouseDown → performDrag`（全窗任意处），右键透传给 contextMenu
- **缩放**：`ResizeHandlesView` 8 条隐形条带，覆写 `hitTest` 只在条带上接事件（否则整层吞点击）；`NSCursor.frameResize(position:directions:)` 显示对应光标
- **吸附**：无系统 API（AppKit 全量头文件检索确认），`windowDidMove` 中对所在屏 `visibleFrame` 四边/角 14pt 阈值 `setFrame`，`isSnapping` 防递归
- **持久化**：左上角坐标 + 尺寸入 UserDefaults，500ms debounce；borderless 阴影用 `invalidateShadow()` 维护

### 7. 全局热键 HotKeyService

Carbon `RegisterEventHotKey`——macOS 26 SDK 仍未废弃、**不需要辅助功能权限**（KeyboardShortcuts 等库底层同为 Carbon）。预设 `⌃⌘K`（K=K线）/ `⌃⌥⌘K` / `⌥⌘K`，注册失败（OSStatus ≠ noErr）自动落到下一预设。

Swift 6 并发注意：C 回调捕获任何非 Sendable 值都会报错。解法：`nonisolated(unsafe) static var active` 持有服务实例，回调闭包零捕获，内部 `MainActor.assumeIsolated`（Carbon 事件本就在主 runloop 派发）。

### 8. 登录项与状态栏

- **LoginItemService**：`SMAppService.mainApp` 主路径 + osascript System Events fallback（ad-hoc 签名也能用），仅 .app 捆绑模式生效
- **StatusItemController**：`NSStatusItem` + `menuNeedsUpdate` 每次打开菜单刷新勾选（与右键菜单经同一 `AppActions`，状态双向同步）
- **本地化**：`String(localized:)` + `en` / `zh-Hans` `.strings`，跟随系统语言

## 验证体系

| 验证 | 手段 | 结果 |
|---|---|---|
| K 线相位边界 | 独立脚本 14 用例（含两处整 5 分收盘点） | ALL PASS |
| 光晕全周均匀 | `--glow-preview` 六点同距采样 | 偏差 ≤1/255，PASS |
| 光晕任意底可读 | 黑/白四象限对照图目检 | 通过 |
| 闪光节奏 | `TC_CANDLE_LEN_SECONDS=30` 实机演练 | 黄×3 / 红×5 |
| 时间对齐 | 与菜单栏时钟逐秒对照、睡眠唤醒后校准 | 分秒不差 |
| 失焦玻璃 | 实机点击他处对比 | 全透明不变 |

## 参考

- HIG [Materials · Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials)——regular/clear 分工、克制使用
- WWDC25-219 *Meet Liquid Glass*、WWDC25-310 *Build an AppKit app with the new design system*（`NSGlassEffectView.contentView` 用法）
- 运行时探测笔记：`NSGlassEffectView` 53 个 selector 中的 `_windowChangedKeyState` / `_subduedState` / `_scrimState`（macOS 26.3 实测）
- 工程形态与登录项/面板模式源自同作者 economic-calendar widget
