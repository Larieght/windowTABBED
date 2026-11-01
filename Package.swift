// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "windowTABBED",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "windowTABBED",
            path: "Sources/windowTABBED"
        )
    ],
    swiftLanguageModes: [.v5]
)
