# MobaLike — 一个 MobaXterm 风格的 Mac 原生 SSH / 串口 终端

用 Swift + SwiftUI 写的、界面和基本用法对齐 MobaXterm 的轻量终端工具。
**只做两件事**：SSH 远程终端、串口调试终端。会话可保存成树形（文件夹分组），
标签页多开，切换标签不打断连接。

---

## 功能

| 能力 | 说明 |
| --- | --- |
| SSH 终端 | 复用系统 `/usr/bin/ssh` + PTY，密码、主机指纹、交互模式都在终端里进行 |
| 串口终端 | termios 打开 `/dev/cu.*`，支持波特率 / 数据位 / 校验 / 停止位 / 流控 |
| 本地终端 | 打开一个本地 Shell 标签（类似 MobaXterm 的本地终端） |
| 会话管理 | 左侧树形会话栏，支持文件夹分组、新建/编辑/重命名/删除 |
| 标签页 | 主区域多标签，切换不中断连接，标题跟随远程 OSC 设置 |
| 持久化 | 会话配置保存到 `~/Library/Application Support/MobaLike/sessions.json` |

## 界面布局

```
┌────────────────────────────────────────────────────────────┐
│                [标签页条: SSH-1 | 串口-2 | 本地 | ＋]        │
│  ┌────┬────────────┬─────────────────────────────────────── │
│  │功能条│  会话列表   │                                       │
│  │SSH │ folder     │       终端区（SwiftTerm）               │
│  │串口 │  ├ ssh     │                                       │
│  │本地 │  └ 串口    │                                       │
│  └────┴────────────┴─────────────────────────────────────── │
```

- 左侧功能条：会话面板开关（==用来切换左侧会话栏显隐==）、SSH 快速新建、串口快速新建、本地终端。
- 会话栏：双击打开会话；右键有新建/编辑/重命名/删除菜单。
- 顶栏 `＋` 或 ⌘N 新建会话，⌘T 新建本地终端。

## 如何构建运行

> **状态（已实测）**：本项目代码已经在 **swift.org 官方 Swift 6.0.3 工具链**上
> `swift build`（debug + release）**编译通过**，应用可启动运行、可打包成
> `MobaLike.app`。
>
> 说明：本机 `CommandLineTools` 自带的 Swift 与 SDK 版本不匹配（无法编译），
> 因此系统 `swift` 命令暂时不可用。有两种解决路径：
> 1. **装完整版 Xcode**（App Store 免费，约 12GB），一切恢复正常（推荐）；
> 2. 暂时用已解包的官方工具链编译（见下「方式四」）。
>
> 另：Swift 6.0.3 编译器有一个 bug——`@StateObject + @MainActor` 的调试信息会让
> 编译器在 IRGen 阶段崩溃；工程已在 `Package.swift` 里通过
> `-disable-round-trip-debug-types` 绕行（对最终产物无影响）。

### 方式一：用 Xcode（推荐）

1. 从 App Store 安装 Xcode，装好后执行：
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
2. 打开工程：
   ```bash
   open /Users/nana/Documents/test/MobaLike/Package.swift
   ```
   Xcode 会打开这个 Swift Package 工程，选择 `MobaLike` scheme（可执行目标）后 ⌘R 运行。
   首次运行若提示“无法验证开发者”，在 **Signing & Capabilities** 里签名选择
   **Sign to Run Locally**（本地运行，不需要开发者账号）。

### 方式二：命令行构建 + 打成 .app

装好 Xcode 后（工具链匹配了即可）：
```bash
cd /Users/nana/Documents/test/MobaLike
./scripts/make-app.sh release     # 产出 build/MobaLike.app
open build/MobaLike.app
```
（ad-hoc 签名，仅限本机使用。）

### 方式三：直接命令行跑（调试）

```bash
cd /Users/nana/Documents/test/MobaLike
swift run                          # 会以裸二进制弹出窗口
```

### 方式四：（没装 Xcode 时的临时办法）用解包的官方工具链

本机已把 swift.org 官方 6.0.3 工具链解包在
`/Users/nana/Documents/test/.scratch-toolchain/root`（可删除，非工程一部分）：
```bash
cd /Users/nana/Documents/test/MobaLike
export SWIFT=/Users/nana/Documents/test/.scratch-toolchain/root/usr/bin/swift
$SWIFT build -c release
./scripts/make-app.sh release      # 打包 build/MobaLike.app（脚本会读 $SWIFT）
open build/MobaLike.app
```

## 使用步骤（SSH 示例）

1. 左侧功能条点 **SSH** 或按 ⌘N → 填主机/端口/用户名 → “保存后立即连接”。
2. 终端里会进入 `ssh -tt user@host` 交互流程：
   - 首次连接问 `yes/no` 确认指纹 → 敲 `yes`；
   - 密码留空则直接在终端里输入（和 MobaXterm 交互登录一致）。
3. 通过 `exit` 退出时，标签标题会加上“（已断开）”，点 × 关闭即可。

## 串口使用（Serial 示例）

1. 左侧功能条点 **串口** → 选择设备（`/dev/cu.*`，可点刷新）、波特率等 → 确定。
2. 连接成功后终端里会有提示，直接收发数据。
3. 常用波特率：115200（默认）、9600、57600、230400 等。

## 技术栈 / 依赖

- 语言/框架：Swift 6 · SwiftUI · AppKit
- 终端模拟：**[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)**（MIT，已本地固定 v1.20.0，见 `SwiftTermRef/`）
- SSH：系统 `/usr/bin/ssh`
- 串口：POSIX termios + poll（`Sources/MobaLike/Terminal/SerialPort.swift`，零第三方依赖）

## 工程结构

```
Sources/MobaLike/
├── MobaLikeApp.swift              入口（菜单、应用生命周期）
├── Models/
│   ├── SessionConfig.swift        会话配置（SSH / 串口）
│   └── SessionTree.swift          会话树（文件夹 + 会话节点）
├── Services/
│   ├── AppLocations.swift         数据目录
│   └── AppModel.swift             全局状态（会话树 + 标签页 + 弹窗）
├── Terminal/
│   ├── TermSessionController.swift  标签页模型 + 控制器基类 + 注册表
│   ├── TermHostView.swift           AppKit -> SwiftUI 桥
│   ├── SSHViewController.swift     SSH 会话
│   ├── LocalShellViewController.swift 本地终端
│   ├── SerialViewController.swift  串口会话
│   └── SerialPort.swift           串口封装
└── UI/
    ├── MainView.swift / RailView.swift / SidebarView.swift
    ├── TabBarView.swift / TerminalAreaView.swift
    └── NewSessionSheet.swift      新建/编辑会话对话框
```

## Roadmap（后续可加）

- [ ] 密码自动登录（检测 `password:` 提示后自动发送）
- [ ] SFTP 文件面板
- [ ] 会话导入/导出
- [ ] SSH 密钥文件选择面板
- [ ] 深浅色主题跟随系统
- [ ] 串口日志记录

## 说明

- 本工具仅供个人本地使用，ad-hoc 签名即可运行，无需上架 App Store。
- 会话配置（含密码字段）以明文 JSON 存在本机，介意可在后续版本接入系统钥匙串（Keychain）。
