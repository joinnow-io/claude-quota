// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudeQuota",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeQuota",
            path: "Sources/ClaudeQuota",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
