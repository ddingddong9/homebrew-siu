// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "mac-arrow",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mac-arrow", targets: ["MacArrow"])
    ],
    targets: [
        .executableTarget(
            name: "MacArrow",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network")
            ]
        )
    ]
)
