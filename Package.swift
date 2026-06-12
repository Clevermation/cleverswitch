// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleverSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        // Reine, plattformnahe Logik — ohne UI, frei testbar.
        .target(name: "CleverSwitchKit"),
        // Menüleisten-App (SwiftUI MenuBarExtra, LSUIElement).
        .executableTarget(
            name: "CleverSwitch",
            dependencies: ["CleverSwitchKit"]
        ),
        .testTarget(
            name: "CleverSwitchKitTests",
            dependencies: ["CleverSwitchKit"]
        ),
    ]
)
