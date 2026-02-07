// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftCLI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "CLISDK",
            targets: ["CLISDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .macro(
            name: "CLIMacrosSDK",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/CLIMacrosSDK"
        ),
        .target(
            name: "CLISDK",
            dependencies: [
                .target(name: "CLIMacrosSDK"),
            ],
            path: "Sources/CLISDK",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "CLISDKTests",
            dependencies: [
                .target(name: "CLISDK"),
                .target(name: "CLIMacrosSDK"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/CLISDKTests"
        ),
    ]
)
