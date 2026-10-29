// swift-tools-version:5.10
import PackageDescription

// HoverboxCore holds all logic that does not need AppKit (shake detection,
// shelf model, persistence, rules) so it can be unit-tested with `swift test`.
// The macOS app lives in App/ and is generated into an Xcode project by
// XcodeGen (see project.yml and README.md).
let package = Package(
    name: "HoverboxCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HoverboxCore", targets: ["HoverboxCore"]),
    ],
    targets: [
        .target(name: "HoverboxCore", path: "Sources/HoverboxCore"),
        .testTarget(name: "HoverboxCoreTests", dependencies: ["HoverboxCore"], path: "Tests/HoverboxCoreTests"),
    ]
)
