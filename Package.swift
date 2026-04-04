// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterDisplayFree",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BetterDisplayFree", targets: ["BetterDisplayFree"])
    ],
    targets: [
        .executableTarget(
            name: "BetterDisplayFree",
            dependencies: [],
            path: "Sources/HiDPITool",
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/HiDPITool/Bridge/CGVirtualDisplayPrivate.h"])
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
