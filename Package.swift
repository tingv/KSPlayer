// swift-tools-version:5.9
import Foundation
import PackageDescription

#if swift(>=6.0)
let swiftConcurrency = SwiftSetting.enableUpcomingFeature("StrictConcurrency")
let swiftLanguageVersions: [PackageDescription.SwiftVersion] = [.v6]
#else
let swiftConcurrency = SwiftSetting.enableExperimentalFeature("StrictConcurrency")
let swiftLanguageVersions: [PackageDescription.SwiftVersion] = [.v5]
#endif
let package = Package(
    name: "KSPlayer",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_15), .macCatalyst(.v14), .iOS(.v13), .tvOS(.v13),
                .visionOS(.v1)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "KSPlayer",
            // todo clang: warning: using sysroot for 'iPhoneSimulator' but targeting 'MacOSX' [-Wincompatible-sysroot]
//            type: .dynamic,
            targets: ["KSPlayer"]
        ),
        .library(
            name: "MPVPlayer",
//            type: .dynamic,
            targets: ["MPVPlayer"]
        ),
    ],
    targets: [
        .target(
            name: "MPVPlayer",
            dependencies: [
                "KSPlayer",
                .product(name: "libmpv", package: "FFmpegKit"),
//                .product(name: "libbluray", package: "FFmpegKit", condition: .when(platforms: [.macOS])),
//                .product(name: "libzvbi", package: "FFmpegKit", condition: .when(platforms: [.macOS, .iOS, .tvOS, .visionOS])),
            ],
            swiftSettings: [
                swiftConcurrency,
            ]
        ),
        .target(
            name: "KSPlayer",
            dependencies: [
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                "DisplayCriteria",
            ],
            resources: [.process("Metal/Resources")],
            swiftSettings: [
                swiftConcurrency,
            ]
        ),
        .target(
            name: "DisplayCriteria"
        ),
        .testTarget(
            name: "KSPlayerTests",
            dependencies: ["KSPlayer"],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageVersions: swiftLanguageVersions
)

var ffmpegKitPath = FileManager.default.currentDirectoryPath + "/FFmpegKit"
if !FileManager.default.fileExists(atPath: ffmpegKitPath) {
    ffmpegKitPath = FileManager.default.currentDirectoryPath + "/../FFmpegKit"
}

if !FileManager.default.fileExists(atPath: ffmpegKitPath), let url = URL(string: #file) {
    let path = url.deletingLastPathComponent().path
    // 解决用xcode引入spm的时候，依赖关系出错的问题
    if !path.contains("/checkouts/") {
        ffmpegKitPath = path + "/../FFmpegKit"
    }
}

if FileManager.default.fileExists(atPath: ffmpegKitPath + "/Package.swift") {
    package.dependencies += [
        .package(path: ffmpegKitPath),
    ]
} else {
    package.dependencies += [
        .package(url: "git@github.com:TracyPlayer/FFmpegKit.git", from: "7.1.0"),
    ]
}
