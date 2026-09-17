// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Malgyeol",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Malgyeol",
            path: "App/Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("Security"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
