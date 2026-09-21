// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "siu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "siu", targets: ["MacArrow"])
    ],
    targets: [
        .executableTarget(
            name: "MacArrow",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network")
            ]
        )
    ]
)
