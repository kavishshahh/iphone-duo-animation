// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Still",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Still", targets: ["Still"])],
    targets: [
        .target(name: "FoldCore"),
        .executableTarget(name: "Still", dependencies: ["FoldCore"],
            resources: [.copy("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"), .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("MetalKit")
            ]),
        .testTarget(name: "FoldCoreTests", dependencies: ["FoldCore"])
    ],
    swiftLanguageVersions: [.v5]
)
