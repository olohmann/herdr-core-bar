// swift-tools-version: 6.2
import PackageDescription

let kitSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let appSettings: [SwiftSetting] = kitSettings + [
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "HerdrCoreBar",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "HerdrCoreBar", targets: ["HerdrCoreBar"]),
        .library(name: "HerdrCoreKit", targets: ["HerdrCoreKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(
            name: "HerdrCoreKit",
            swiftSettings: kitSettings
        ),
        .executableTarget(
            name: "HerdrCoreBar",
            dependencies: [
                "HerdrCoreKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: appSettings,
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "HerdrCoreKitTests",
            dependencies: ["HerdrCoreKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: kitSettings
        ),
        .testTarget(
            name: "HerdrCoreBarTests",
            dependencies: ["HerdrCoreBar", "HerdrCoreKit"],
            swiftSettings: appSettings
        ),
    ]
)
