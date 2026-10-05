import XCTest

/// The acceptance criteria no test can run, only read: that the menu-bar host is *gone*, that nothing
/// tracks the cursor over the Glance, that nothing posts a notification, that the forced dark scheme
/// stops at the notch window, that the notch is drawn by one window rather than two (#22), and that the
/// motion #22 added is the window's shape and not the reading's. Each is checked by scanning `Sources/`
/// for the API that would make it false — the same shape `CommittedCaptureTests` and
/// `FixtureCorpusTests` use for the claims a running test cannot reach.
///
/// They live together because they are one kind of thing: an invariant this app keeps by the
/// **absence** of a control, which #17 found does not survive a UI move unless somebody guards the
/// absence. A hover that expanded the Panel would satisfy every functional test in this repository
/// while breaking ADR-0006 and CONTEXT invariant 14, because there is no call to make and no read to
/// count — the only check that catches it is that the call does not exist. The same goes for a second
/// window at the notch, and for a `withAnimation` in a Panel that is meant to be revealed rather than
/// to move.
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

    /// AC 4, checked as an absence: the forced dark scheme belongs to the notch window and reaches
    /// nothing else. ADR-0007 leaves Settings an ordinary window that follows the system appearance,
    /// and the one way to break that from the notch side is to force the appearance somewhere broader
    /// than the one window — on `NSApp`, on the scene, or in the Panel's own view tree.
    func test_theForcedAppearanceIsTheNotchWindow_ownAndNoonesElse() throws {
        let marks = ["NSAppearance", "appearance =", "preferredColorScheme", "\\.colorScheme"]

        for url in try swiftFiles(under: "Sources") {
            guard url.lastPathComponent != "NotchWindow.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for mark in marks {
                XCTAssertFalse(
                    text.contains(mark),
                    "\(url.lastPathComponent) forces an appearance with \(mark) — only the notch "
                        + "window may; Settings follows the system (#21 AC 4)"
                )
            }
        }

        let window = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/SprintPulse/NotchWindow.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            window.contains("NSAppearance(named: .darkAqua)"),
            "the notch window must name the dark scheme itself, or the Panel is a light card "
                + "under a black band in Light Mode (#21 AC 1)"
        )
        // …and name it on the *window*. Setting `NSApp.appearance` would be one line shorter and would
        // take Settings with it, which is the half of AC 4 that only shows on an Operator's machine.
        XCTAssertFalse(
            window.contains("NSApp.appearance"),
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

    // MARK: - One window, and what is not allowed to move (#22)

    /// AC 1's premise, checked as a count: the notch host draws *one* window. #21 had two windows
    /// aligned to look like one silhouette and needed a point of overlap and a stacking-order trick to
    /// hold the join closed; #22 retires both, and the way that regresses is quietly — somebody adds a
    /// second panel for a new surface, every geometry test keeps passing on the two rects it can see,
    /// and the seam comes back on screen. So the absence of the second window is what gets guarded.
    ///
    /// The other half of the same claim is that only the window draws the black. A `NotchShape` filled
    /// inside the band or the reading is #21's design coming back by itself — a second shape with its
    /// own rounded corners, sitting inside the one that is supposed to be growing — and it would show up
    /// on screen as a nick at the join, which is exactly what a screenshot caught last time and no
    /// assertion on rects ever did.
    func test_theNotchHostDrawsOneWindowAndFillsItOnce() throws {
        var panels: [String] = []
        var shapes: [String] = []

        for url in try swiftFiles(under: "Sources") {
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains(": NSPanel") {
                panels.append(url.lastPathComponent)
            }
            if url.lastPathComponent != "NotchShape.swift", text.contains("NotchShape") {
                shapes.append(url.lastPathComponent)
            }
        }

        XCTAssertEqual(
            panels, ["NotchWindow.swift"],
            "the Glance and the Panel are one window that resizes (#22 AC 1) — a second NSPanel at the "
                + "notch is the arrangement this ticket retires"
        )
        XCTAssertEqual(
            shapes, [],
            "only `NotchSilhouette` fills the notch's black, and the window is what draws it (#22 AC 1)"
        )
    }

    /// AC 2, from the side the host's own tests cannot reach: the read is issued on the click and never
    /// when the shape lands. `NotchHost` is the only caller of `windowDidAppear` in the app, and the
    /// window layer — which is the only thing that knows when a morph has finished — must not contain
    /// the call at all. A `Task { await panel.windowDidAppear() }` moved into an animation's completion
    /// handler would keep every read-count test in this repository green while answering the Operator a
    /// fifth of a second late, which is exactly the kind of claim an absence check is for.
    func test_theWindowLayerNeverIssuesARead() throws {
        let window = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/SprintPulse/NotchWindow.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            window.contains("windowDidAppear"),
            "the notch window must not read the Board — the click does, before the morph starts (#22 AC 2)"
        )

        let host = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/SprintPulse/NotchHost.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            host.contains("windowDidAppear"),
            "and the click is still the one thing that issues it (invariant 14)"
        )
    }

    /// AC 1's second clause — "nothing else on the Panel moves" — checked as an absence in the two views
    /// whose pixels must stay put while the window's shape grows. The morph is the *window* resizing
    /// (`NotchWindow`), which is why that file is not in this scan; a `withAnimation` inside the reading
    /// would be a second motion laid over it, and #9's rule that nothing in the panel loops or animates
    /// is the rule this keeps true after #22 put motion into the app.
    func test_nothingInTheNotchSurfacesOwnViewsAnimates() throws {
        let marks = ["withAnimation", ".animation(", ".transition(", "AnyTransition"]

        for name in ["PanelView.swift", "GlanceView.swift", "NotchShape.swift"] {
            let text = try String(
                contentsOf: repoRoot.appendingPathComponent("Sources/SprintPulse/\(name)"),
                encoding: .utf8
            )
            for mark in marks {
                XCTAssertFalse(
                    text.contains(mark),
                    "\(name) animates itself with \(mark) — the only motion at the notch is the window's "
                        + "own shape growing (#22 AC 1, #9)"
                )
            }
        }
    }
}
