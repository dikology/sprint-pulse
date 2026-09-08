// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SprintPulse",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SprintPulseCore", targets: ["SprintPulseCore"]),
        .executable(name: "SprintPulse", targets: ["SprintPulse"]),
    ],
    targets: [
        // The domain model, the Jira gateway, and the fixture corpus. No UI dependency:
        // this target must build without SwiftUI (ADR-0005).
        .target(
            name: "SprintPulseCore",
            resources: [.copy("Fixtures")]
        ),
        // The macOS menu-bar app. A thin view layer; it holds all platform concerns and no
        // forecast logic.
        .executableTarget(
            name: "SprintPulse",
            dependencies: ["SprintPulseCore"]
        ),
        .testTarget(
            name: "SprintPulseCoreTests",
            dependencies: ["SprintPulseCore"]
        ),
    ]
)
