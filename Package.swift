// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glowbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GlowbarApp", targets: ["GlowbarApp"]),
        .executable(name: "glowbar", targets: ["glowbar"]),
        .library(name: "GlowbarKit", targets: ["GlowbarKit"]),
    ],
    targets: [
        .target(
            name: "GlowbarKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "GlowbarApp", dependencies: ["GlowbarKit"]),
        .executableTarget(name: "glowbar", dependencies: ["GlowbarKit"]),
        .testTarget(name: "GlowbarKitTests", dependencies: ["GlowbarKit"]),
    ]
)
