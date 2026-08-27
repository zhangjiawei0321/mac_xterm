// swift-tools-version:5.9
//
//  MobaLike - 一个 MobaXterm 风格的 Mac 原生 SSH / 串口 终端工具
//  依赖本地 SwiftTerm 仓库（MIT 协议，已固定到 v1.20.0）
//
import PackageDescription

let package = Package(
    name: "MobaLike",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "SwiftTermRef")
    ],
    targets: [
        .executableTarget(
            name: "MobaLike",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTermRef")
            ],
            path: "Sources/MobaLike"
        )
    ]
)
