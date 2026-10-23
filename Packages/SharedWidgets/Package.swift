// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SharedWidgets",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SharedWidgets", targets: ["SharedWidgets"])],
    targets: [
        .target(name: "SharedWidgets"),
        .testTarget(name: "SharedWidgetsTests", dependencies: ["SharedWidgets"]),
    ],
    swiftLanguageModes: [.v5]
)
