import XCTest

/// Three acceptance criteria that no test can run, only read: that the menu-bar host is *gone*, that
/// nothing tracks the cursor over the Glance, and that nothing posts a notification. Each is checked
/// by scanning `Sources/` for the API that would make it false — the same shape
/// `CommittedCaptureTests` and `FixtureCorpusTests` use for the claims a running test cannot reach.
///
/// They live together because they are one kind of thing: an invariant this app keeps by the
/// **absence** of a control, which #17 found does not survive a UI move unless somebody guards the
/// absence. A hover that expanded the Panel would satisfy every functional test in this repository
/// while breaking ADR-0006 and CONTEXT invariant 14, because there is no call to make and no read to
/// count — the only check that catches it is that the call does not exist.
final class SourceGuardTests: XCTestCase {
    /// The repository root, from this file's own compiled-in path.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SprintPulseAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    private func swiftFiles(under directory: String) throws -> [URL] {
        let root = repoRoot.appendingPathComponent(directory)
        let walked = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "found nothing under \(directory), so these tests would check nothing"
        )
        let files = walked.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no Swift sources under \(directory) — the scan checked nothing")
        return files
    }


    /// AC 1, checked rather than promised: `MenuBarExtra` is gone from the app's sources — not kept
    /// as a fallback, because two hosts would mean every Panel change is made twice (ADR-0006) —
    /// and the app still refuses the Dock icon a windowed one would have.
    func test_theAppHasNoMenuBarScene_andStillNoDockIcon() throws {
        for url in try swiftFiles(under: "Sources") {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                text.contains("MenuBarExtra"),
                "\(url.lastPathComponent) still carries a menu-bar scene — #19 removes the host, not the label"
            )
        }

        let app = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/SprintPulse/SprintPulseApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            app.contains("setActivationPolicy(.accessory)"),
            "a notch instrument is still not a Dock icon"
        )
    }

    /// AC 2's first clause, and the reason the read stayed on the click (ADR-0006): nothing in the
    /// app may track the cursor crossing the Glance. A hover that expanded the Panel would turn
    /// walking the mouse over the top of the screen into polling — on a self-hosted Jira usually
    /// behind a VPN. An invariant kept by the absence of a control is only kept while somebody
    /// guards the absence, which is #17's lesson applied to this surface.
    func test_nothingInTheAppTracksTheCursorOverTheGlance() throws {
        let marks = [
            "onHover", "NSTrackingArea", "addTrackingArea",
            "mouseEntered", "mouseMoved", "cursorUpdate",
        ]

        for url in try swiftFiles(under: "Sources") {
            let text = try String(contentsOf: url, encoding: .utf8)
            for mark in marks {
                XCTAssertFalse(
                    text.contains(mark),
                    "\(url.lastPathComponent) tracks the cursor with \(mark) — the Glance must read nothing on hover"
                )
            }
        }
    }

    /// AC 8: the instrument tells you when you look at it and never otherwise
    /// (`docs/agents/product.md` → Notifications).
    func test_theAppPostsNoNotifications() throws {
        let marks = [
            "UNUserNotificationCenter", "NSUserNotification",
            "requestAuthorization", "addNotificationRequest",
        ]

        for url in try swiftFiles(under: "Sources") {
            let text = try String(contentsOf: url, encoding: .utf8)
            for mark in marks {
                XCTAssertFalse(
                    text.contains(mark),
                    "\(url.lastPathComponent) reaches for \(mark) — Sprint Pulse never notifies"
                )
            }
        }
    }

    // MARK: - Whose appearance is whose (#21)

    /// AC 4, checked as an absence: the forced dark scheme belongs to the notch windows and reaches
    /// nothing else. ADR-0007 leaves Settings an ordinary window that follows the system appearance,
    /// and the one way to break that from the notch side is to force the appearance somewhere broader
    /// than the two windows — on `NSApp`, on the scene, or in the Panel's own view tree.
    ///
    /// AC 1's other half is here too: the notch surfaces are black with dark content, and a
    /// `windowBackgroundColor` card is the system surface that was taken out.
    func test_theForcedAppearanceIsTheNotchWindows_ownAndNoonesElse() throws {
        let marks = ["NSAppearance", "appearance =", "preferredColorScheme", "\\.colorScheme"]

        for url in try swiftFiles(under: "Sources") {
            guard url.lastPathComponent != "NotchWindows.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for mark in marks {
                XCTAssertFalse(
                    text.contains(mark),
                    "\(url.lastPathComponent) forces an appearance with \(mark) — only the two notch "
                        + "windows may; Settings follows the system (#21 AC 4)"
                )
            }
        }

        let windows = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/SprintPulse/NotchWindows.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            windows.contains("NSAppearance(named: .darkAqua)"),
            "the notch windows must name the dark scheme themselves, or the Panel is a light card "
                + "under a black band in Light Mode (#21 AC 1)"
        )
        // …and name it on the *window*. Setting `NSApp.appearance` would be one line shorter and would
        // take Settings with it, which is the half of AC 4 that only shows on an Operator's machine.
        XCTAssertFalse(
            windows.contains("NSApp.appearance"),
            "the scheme must be per window — on NSApp it reaches the Settings window too (#21 AC 4)"
        )
    }

    /// AC 1: the notch surfaces carry no system surface colour at all. `windowBackgroundColor` and the
    /// separator stroke are what made the Panel look like a system card; the band, the Panel, and the
    /// menu it hosts are drawn from `NotchPalette` now, and a system colour creeping back into any of
    /// those files would be visible in Light Mode only — which is the half of this AC no running test
    /// can reach.
    func test_theNotchSurfacesCarryNoSystemSurfaceColour() throws {
        let marks = ["windowBackgroundColor", "separatorColor", "controlBackgroundColor", "textBackgroundColor"]

        // `FlowStateMenus` is the Unmapped Status menu AC 1 names by hand, so it is in the scan even
        // though it is shared with the Status Map editor in Settings.
        for name in ["PanelView.swift", "GlanceView.swift", "NotchShape.swift", "FlowStateMenus.swift"] {
            let text = try String(
                contentsOf: repoRoot.appendingPathComponent("Sources/SprintPulse/\(name)"),
                encoding: .utf8
            )
            for mark in marks {
                XCTAssertFalse(
                    text.contains(mark),
                    "\(name) still fills itself with \(mark) — the notch host's surfaces are its own black"
                )
            }
        }
    }
}
