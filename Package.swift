// swift-tools-version:5.9
//
//  MobaLike - 一个 MobaXterm 风格的 Mac 原生 SSH / 串口 终端工具
//  依赖本地 SwiftTerm 仓库（MIT 协议，已固定到 v1.20.0）
//
import PackageDescription

let package = Package(
    name: "MobaLike",
    platforms: [
        .macOS(.v14)
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
            path: "Sources/MobaLike",
            // 规避 Swift 6.0.3 编译器在 IRGen 阶段因 @StateObject+@MainActor
            // 调试信息往返导致的崩溃（"Failed to reconstruct type ..."）
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-round-trip-debug-types"])
            ]
        ),
        .testTarget(
            name: "MobaLikeTests",
            dependencies: ["MobaLike"],
            path: "Tests/MobaLikeTests"
        )
    ]
)
