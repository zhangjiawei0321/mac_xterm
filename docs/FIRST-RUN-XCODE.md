# MobaLike 第一次在 Xcode 里编译运行的步骤

> 前提：已从 App Store 装好 Xcode（装好后可能要先启动一次 Xcode，接受许可协议）。

## 1. 让系统命令指向 Xcode 的工具链

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# 验证（此时应显示 Xcode 路径而不是 CommandLineTools）：
xcode-select -p
swift --version        # 应显示带 (Apple Swift ... /Applications/Xcode.app...) 的版本
```

## 2. 打开工程

```bash
open /Users/nana/Documents/test/MobaLike/Package.swift
```

Xcode 会以 Swift Package 方式打开（左侧是 Sources 文件树）。

## 3. 运行

- 顶部选 **MobaLike** scheme，设备/目的地选 **My Mac**；
- 直接 **⌘R**。
- 首次编译会解析依赖（SwiftTerm 是本地路径依赖 `SwiftTermRef/`，无需联网），过程约 1–2 分钟。

若提示签名问题（"Failed to build because..." 或 "my Mac" 运行被拒）：
**Target → Signing & Capabilities → 签名选 `Sign to Run Locally`**（本地跑不需要开发者账号，也不会上架）。

## 4. 替代：命令行构建 + 打 .app

```bash
cd /Users/nana/Documents/test/MobaLike
swift build -c release          # 或 swift run 直接以裸二进制跑
./scripts/make-app.sh release   # 产出 build/MobaLike.app
open build/MobaLike.app
```

## 5. 首次编译若有报错

把 `Xcode 顶部的报错文字`原样发我，我来修（当前代码已过语法级检查，
剩余大概率只是个别类型小错，都在可控范围）。

## 6. 编译通过后

打开 `docs/ACCEPTANCE.md` 逐项验证功能是否真的可用；把打勾结果/失败项告诉我。
