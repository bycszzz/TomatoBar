# CLAUDE.md

本文件供未来的 Claude Code 实例阅读，帮助快速建立对本仓库的心智模型。

本仓库是 fork 自 `AuroraWright/TomatoBar` 的 macOS 菜单栏 Pomodoro 计时器，**仅供个人自用改造**，不发布、不打算上 App Store。

## 关键文件速览

| 文件 | 作用 |
| --- | --- |
| `TomatoBar/Timer.swift` | `TBTimer`：状态机宿主、`@AppStorage` 偏好、URL Scheme 入口、`DispatchSourceTimer` 调度、暂停/跳过/加一分钟逻辑 |
| `TomatoBar/State.swift` | `TBStateMachine` 类型别名 + 状态 `{idle, work, rest}` 与事件 `{startStop, timerFired, skipEvent}` 的定义 |
| `TomatoBar/App.swift` | `@main` 入口 `TBApp` + `TBStatusItem`（`NSApplicationDelegate`），持有菜单栏 `NSStatusItem` 与 `NSPopover` |
| `TomatoBar/View.swift` | SwiftUI `TBPopoverView`，菜单栏点击后的全部 UI（控制按钮、设置、preset 选择） |
| `TomatoBar.xcodeproj/project.pbxproj` | 签名/Bundle ID/部署目标，个人自用改造时**必须改这里**（见下文） |

## 架构概览

### 模块与数据流

```
NSStatusItem (菜单栏图标/标题)
       │  点击
       ▼
NSPopover ── 内嵌 ── NSHostingView(TBPopoverView)  ←─ SwiftUI 绑定 ──┐
                                                                     │
                                                              @ObservedObject
                                                                     │
                              ┌────────────────────────────── TBTimer (ObservableObject)
                              │                                       │
                              ├── TBStateMachine (SwiftState)          │
                              │     idle ⇄ work ⇄ rest                 │
                              │     transition handlers 调用 ↓         │
                              │                                       │
                              ├── TBStatusItem.shared.setIcon/setTitle │
                              ├── TBPlayer  (windup / ding / ticking)  │
                              ├── TBNotificationCenter (UN + 动作回调) │
                              ├── DoNotDisturbHelper (Apple Events)    │
                              ├── MaskView (全屏遮罩，可选)            │
                              └── logger (JSON 事件追加到沙盒日志)     │
                                                                     │
       外部触发：                                                    │
         - KeyboardShortcuts 全局热键 ────────────────────────────────┤
         - tomatobar:// URL (NSAppleEventManager kAEGetURL) ──────────┤
         - UNNotificationAction (skipRest) ──────────────────────────┘
```

所有用户操作（点击 / 热键 / URL / 通知动作）最终都汇聚为向 `stateMachine` 发送一个事件（`<-! .startStop` / `.skipEvent` / `.timerFired`）。**禁止绕过状态机直接改图标、播声音、切 DND**——这些副作用都挂在 transition handler 上。

### 状态转换（文字版状态图）

源码注释里的 ASCII 图 (`Timer.swift:80`)：

- `idle ──startStop──▶ work`（当 `startWith == .work`）
- `idle ──startStop──▶ rest`（当 `startWith == .rest`）
- `work ──startStop──▶ idle`
- `work ──timerFired/skipEvent──▶ idle`（当 `stopAfter == .work`）
- `work ──timerFired/skipEvent──▶ rest`（其他情况）
- `rest ──startStop──▶ idle`
- `rest ──timerFired/skipEvent──▶ idle`（当 `stopAfter == .rest`，或 `stopAfter == .longRest` 且达到 `workIntervalsInSet`）
- `rest ──timerFired/skipEvent──▶ work`（其他情况）

Handler 注册位置：`Timer.swift:122-130`，关键的 `onIdleStart` / `onWorkStart` / `onRestStart` / `onRestEnd` / `onWorkEnd` / `onIdleEnd` 分布在 `Timer.swift` 文件后半段。

### tomatobar:// URL Scheme

- 注册：`Info.plist` 的 `CFBundleURLSchemes = ["tomatobar"]`。
- 分发：`TBTimer.init` 里通过 `NSAppleEventManager` 注册 `kAEGetURL` handler → `handleGetURLEvent(_:withReplyEvent:)`（`Timer.swift:149`）。
- 支持的 host（小写）：`startstop` / `pauseresume` / `skip` / `addminute`。新增动作就在此 switch 加一支并暴露对应方法。

### 偏好存储

全部走 `@AppStorage`（`UserDefaults` 包装）。数组类型（presets）能存进 `@AppStorage` 是靠 `Timer.swift:5` 的 `Array: RawRepresentable where Element: Codable` 扩展把它 JSON 序列化成字符串。新增设置时只在 `TBTimer` 加 `@AppStorage` 字段，UI 在 `View.swift` 加绑定即可。

## 常用构建命令

仓库无测试 target；Swift 5.0；最低 macOS 12.0（部署目标 12.3）。依赖：`LaunchAtLogin`、`KeyboardShortcuts`、`SwiftState`，通过 Xcode 的 SwiftPM 集成（**不要手动加包**）。

**Xcode 内**：打开 `TomatoBar.xcodeproj`，scheme 选 `TomatoBar`，⌘R 直接跑。

**命令行 Debug 构建（个人自用最常用）**：

```bash
xcodebuild -project TomatoBar.xcodeproj -scheme TomatoBar \
  -configuration Debug build
# 产物：~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/TomatoBar.app
```

**Release archive（CI 流程，参考用）**：

```bash
xcodebuild archive -project TomatoBar.xcodeproj -scheme TomatoBar \
  -configuration Release -archivePath TomatoBar.xcarchive \
  MARKETING_VERSION=3.5.0-local
xcodebuild -archivePath TomatoBar.xcarchive -exportArchive \
  -exportOptionsPlist export_options.plist -exportPath .
```

`export_options.plist` 的 `method = mac-application`，**不走 notarization**。

**Lint**：根目录 `swiftlint`；`.swiftlint.yml` 关闭了 `trailing_comma`、`opening_brace`。

## 修改时的注意事项

### 沙盒与权限

- 启用 `com.apple.security.app-sandbox`，所以**文件读写仅限沙盒容器**：
  - 日志：`~/Library/Containers/com.github.ivoronin.TomatoBar/Data/Library/Caches/TomatoBar.log`
  - 自定义音频：沙盒容器的 Documents 目录里放 `windup` / `ding` / `ticking`（mp3 / m4a / mp4 任一），`TBPlayer` 先查这里再回落 bundle 资源。
  - 若改了 Bundle ID（见下文），容器路径也会跟着变，之前的日志/自定义音频不会自动迁移。
- 唯一额外 entitlement：`com.apple.security.automation.apple-events` + `scripting-targets` 指向 `com.apple.shortcuts.events`。**仅为运行 `macos-focus-mode.shortcut` 切换 Focus/DND**。新增任何需要 Apple Events 的目标都要在 `TomatoBar.entitlements` 显式加进 `scripting-targets`，否则在沙盒里会被拒。
- 首次运行 DND 功能会弹出系统授权（自动化权限），用户拒绝后只能去"系统设置 → 隐私与安全性 → 自动化"里手动开。

### 状态机纪律

- 改流程时优先改 `stateMachine.addRoutes` 的条件闭包，而不是在 handler 里写 if 绕路。
- 想加副作用就 `addAnyHandler`，副作用本身写成 `private func onXxxYyy(ctx: ...)`，与现有命名风格一致。
- `toggleDoNotDisturb` 的 `didSet` 用 `notificationGroup` 串行化 DND 调用，**不要去掉**，否则快速切换时会出现状态错乱。

### 本地化

字符串文件在 `TomatoBar/<lang>.lproj/Localizable.strings`，目前覆盖：`en`, `de`, `el`, `fr`, `it`, `ja`, `pt-BR`, `zh-Hans`。新增 user-facing 字符串：

- 在 **每个** `.lproj/Localizable.strings` 补一行（哪怕只填英文占位），否则其它语言下会显示 key 原文。
- 用 `NSLocalizedString("TBTimer.xxx.title", comment: "...")` 引用，命名沿用 `TBTimer.<事件>.<元素>` 风格。
- 用 `rg -n '"TBTimer\.'` 可快速 cross-check 各语言文件是否同步。

### 隐藏偏好

`@AppStorage("overrunTimeLimit")` 在 `Timer.swift:55`，没有 UI；改完睡眠/挂起容忍策略时记得这里。其它"hidden"偏好沿用此约定：只在 `TBTimer` 声明、不暴露到 `View.swift`。

## 个人自用约束（自由 Apple ID + Personal Team）

**前提**：免费 Apple ID，无付费开发者账户，只能用 Personal Team 签名，**不做 notarization、不上 App Store、不分发**。

需要在 `TomatoBar.xcodeproj/project.pbxproj` 调整（建议在 Xcode → Signing & Capabilities 里改，让 Xcode 自己同步两处 build configuration，避免漏改 Debug/Release）：

- `DEVELOPMENT_TEAM`：把 `LUZK6JBS9B`（上游 team）换成自己 Personal Team 的 10 位 ID（Xcode 会自动填）。
- `PRODUCT_BUNDLE_IDENTIFIER`：`com.github.ivoronin.TomatoBar` 是上游的，Personal Team 下沿用大概率撞已被注册的 wildcard provisioning。改成自己的反域名（如 `dev.<your-handle>.tomatobar`）。**改完后**：
  - `Info.plist` 里 `CFBundleURLName` 也建议同步改（不强制，但建议保持一致）。
  - 沙盒容器路径会变，旧日志/自定义音频迁移要手动 `mv`。
- `CODE_SIGN_STYLE = Automatic` 保留，让 Xcode 用 Personal Team 自动生成 provisioning profile。
- `CODE_SIGN_IDENTITY = "Apple Development"` 保留即可（Personal Team 也能签 Apple Development 证书）。
- **Free 账户限制**：provisioning profile 7 天后过期，过期后 app 启动会失败，需重新在 Xcode 里 Run 一次刷新签名。这是 Apple 的限制，不是 bug。
- 不要碰 `.github/workflows/main.yml`：它面向上游 CI（Xcode 14.1 / macOS 12 runner / GitHub Release），自用时本地构建即可，CI workflow 当成只读参考。
- 不需要 `export_options.plist` 之外的发布配置；想要本地分发给自己其它机器，直接 `cp -R TomatoBar.app /Applications/` 即可（Personal Team 签名能在你自己登录了同一 Apple ID 的机器上运行）。

## 工具偏好

代码搜索用 `rg`、文件查找用 `fd`；不要建议用 `grep` / `find`。
