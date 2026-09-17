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
        // The app's platform concerns are testable at their own seam: the Keychain item, the
        // settings store, and the setup flow that persists through them. Still no network —
        // the identity probe is injected exactly as the transport is on the core side (#10).
        .testTarget(
            name: "SprintPulseAppTests",
            dependencies: ["SprintPulse"]
        ),
    ]
)
