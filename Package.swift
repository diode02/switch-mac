// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwitchMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SwitchMac",
            path: "Sources/SwitchMac",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
