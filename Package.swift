// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BarTidy",
    defaultLocalization: "en",
    // Installed SDK is 27.0; the app bundle requires the current 27.2 runtime.
    platforms: [.macOS("27.0")],
    products: [.executable(name: "BarTidy", targets: ["BarTidy"])],
    targets: [
        .target(name: "NativeBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
        .target(name: "BarTidyCore"),
        .executableTarget(name: "BarTidy", dependencies: ["BarTidyCore", "NativeBridge"], resources: [.process("Resources")]),
        .testTarget(name: "BarTidyCoreTests", dependencies: ["BarTidyCore"]),
        .testTarget(name: "BarTidyTests", dependencies: ["BarTidy"])
    ]
)
