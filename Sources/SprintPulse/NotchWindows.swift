import AppKit
import Combine
import SwiftUI

/// The two windows the notch host draws: a borderless, non-activating panel for the Glance and one
/// for the Panel (#19).
///
/// Nothing here decides *where* anything goes or *when* a read happens — `NotchHost` does, from the
/// screens this type hands it and the gestures it forwards. What is left in AppKit is translation: a
/// placement becomes a `setFrame`, an opening becomes an order-front, a right-click becomes a menu.
///
/// Both windows are panels that do not activate the app, because the instrument is something the
/// Operator glances at while working in another application: clicking it must not bring Sprint Pulse
/// forward or take the keyboard away. Only the Panel takes key status, and only so that Esc, ⌘, and
/// ⌘Q reach it while it has focus. The Glance never does — a surface that cannot be typed into has no
/// business stealing the key window, and that is also what makes a click on it a click rather than a
/// focus change.
///
/// Neither window animates. `animationBehavior = .none` is AC 5 stated in the one place AppKit
/// listens: the Panel appears instantly, because expansion is motion, and motion is reserved for
/// Confidence State changes in M3 (ADR-0006, `docs/agents/product.md`).
@MainActor
final class NotchWindows: NSObject {
    private let panel: PanelModel
    private let host: NotchHost

    private let glanceWindow = GlanceWindow(
        contentRect: CGRect(origin: .zero, size: NotchMetrics.nominalBandSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let panelWindow = PanelWindow(
        contentRect: CGRect(origin: .zero, size: NotchMetrics.defaultPanelSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let glanceSurface = GlanceSurface(
        frame: CGRect(origin: .zero, size: NotchMetrics.nominalBandSize)
    )
    private lazy var panelHosting = NSHostingView(rootView: PanelView(panel: panel))

    /// The click the Glance took this cycle. A key-window loss can *follow* that same click — the
    /// Panel was key, the click landed on a window that cannot become key — and the two are one
    /// gesture seen twice. The click knows what the Operator meant, so a dismissal arriving in the
    /// same cycle is dropped: without this, the click meant to close the Panel could reopen it and
    /// read the Board a second time for one gesture (AC 2).
    private var glanceIsBeingClicked = false

    private var screenObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var contentCancellable: AnyCancellable?

    init(panel: PanelModel, host: NotchHost) {
        self.panel = panel
        self.host = host
        super.init()

        configureGlance()
        configurePanel()
    }

    /// Draws the Glance and starts following the screens. Called once, from the composition root.
    ///
    /// That launch issues no read is not this method's doing — `PanelModel` withholds the live fetch
    /// and `NotchHost` issues it only on a click (invariant 14). What is decided here is only that
    /// the Panel is not on screen until the Operator puts it there.
    func start() {
        refreshPlacement()
        glanceWindow.orderFrontRegardless()

        // The lid closing, an external display attaching, the main screen changing (#19).
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPlacement() }
        }

        // The closer that actually works without asking the Operator for a permission: a click in
        // another application activates that application, and the Panel stops being the key window.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panelWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.glanceIsBeingClicked else { return }
                self.dismissPanel()
            }
        }

        // Best effort beside it: a click in an application that never had the Panel's key status to
        // lose. A global monitor delivers nothing without the input permission this app does not ask
        // for, so the loss above is what closing on an outside click really rests on. Clicks inside
        // Sprint Pulse's own windows never reach either — the Glance covers those.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor in self?.dismissPanel() }
        }

        // The Panel's height is its content's: a reading arriving, or an Unmapped Status being
        // resolved, changes how many rows there are.
        contentCancellable = panel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refitPanel() }
        }
    }

    // MARK: - Building the two panels

    private func configureGlance() {
        configureCommon(glanceWindow)
        // The band is hardware flush with the top edge of the screen, and hardware casts no shadow: a
        // shadow around it is exactly what would read as a window parked on the notch (#25).
        glanceWindow.hasShadow = false
        glanceWindow.contentView = glanceSurface
        glanceWindow.isExcludedFromWindowsMenu = true

        let content = NSHostingView(rootView: GlanceView(
            panel: panel,
            host: host,
            press: { [weak self] in self?.togglePanel() }
        ))
        content.frame = glanceSurface.bounds
        content.autoresizingMask = [.width, .height]
        glanceSurface.addSubview(content)

        glanceSurface.onClick = { [weak self] in self?.togglePanel() }
        glanceSurface.onRightClick = { [weak self] point in self?.popContextMenu(at: point) }
    }

    private func configurePanel() {
        configureCommon(panelWindow)
        panelWindow.contentView = panelHosting
        panelWindow.onDismiss = { [weak self] in self?.dismissPanel() }
        panelWindow.onSettings = { [weak self] in self?.host.openSettings() }
    }

    /// What both windows share: above the menu bar, on every Space, still there when the app is not
    /// the active one, and never animated.
    private func configureCommon(_ window: NSWindow) {
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
    }

    // MARK: - Gestures

    /// The click, and VoiceOver's press action, which arrives here too. One gesture decides both
    /// states of the Panel, so the Glance needs no second control to close it.
    private func togglePanel() {
        glanceIsBeingClicked = true
        host.glanceWasClicked()
        if host.isPanelOpen {
            presentPanel()
        } else {
            panelWindow.orderOut(nil)
        }
        // Cleared on the next turn of the run loop, which is where the observers' `Task`s land —
        // the loss posted while this method ran is queued behind that clear and so is skipped.
        DispatchQueue.main.async { [weak self] in self?.glanceIsBeingClicked = false }
    }

    private func presentPanel() {
        refitPanel()
        guard let layout = host.layout else { return }
        panelWindow.setFrame(layout.panel, display: false)
        panelWindow.makeKeyAndOrderFront(nil)
    }

    /// Idempotent by design: the key-window loss and the global monitor can both describe one click
    /// outside, and a dismissal must not read the Board twice over.
    private func dismissPanel() {
        guard host.isPanelOpen else { return }
        host.panelWasDismissed()
        panelWindow.orderOut(nil)
    }

    /// The Panel hangs from the notch's bottom edge, so a content change keeps that edge and moves
    /// only the bottom. The layout is forced before the size is read: a model change and the redraw
    /// it causes are not the same turn of the run loop, and a stale height would leave the last row
    /// cut off.
    private func refitPanel() {
        panelHosting.layoutSubtreeIfNeeded()
        let size = panelHosting.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        host.panelContentSizeChanged(size)
        guard host.isPanelOpen, let layout = host.layout else { return }
        panelWindow.setFrame(layout.panel, display: true)
    }

    // MARK: - The Glance's context menu

    /// Right-click: the two ways out of an app with no menu bar and no Dock icon — Settings… and
    /// Quit (#19).
    ///
    /// An `NSMenu` rather than SwiftUI's own context menu because this menu belongs to a borderless
    /// panel the app never activates, and because its one non-trivial item — the route to the
    /// `Settings` scene — is handed to this type by the Glance's view, the only place the environment
    /// action that works can be read (`SettingsRoute`).
    private func popContextMenu(at point: NSPoint) {
        let menu = NSMenu()

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Sprint Pulse", action: #selector(quitFromMenu), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: glanceSurface.convert(point, from: nil), in: glanceSurface)
    }

    @objc private func openSettingsFromMenu() {
        host.openSettings()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Screens

    /// The screens as the placement decision needs them, read straight off `NSScreen`, and the two
    /// windows moved to wherever that says they belong.
    ///
    /// The notch's own rect is the strip across the top of a screen that the menu bar cannot use:
    /// `safeAreaInsets.top` is its depth, and its width is what the screen's width loses to
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` — the two unobstructed rects either side of
    /// it. On this Mac that measures 185×32. A screen with no obstruction reports a zero inset, and
    /// `NotchGeometry` draws the band at its top-centre instead, where a notch would be.
    ///
    /// `isMain` is asked of the coordinate space rather than of `NSScreen.main`, which reports the
    /// screen with the keyboard focus: the global Cocoa space is defined by the main display's
    /// bottom-left corner, so the main display is the one whose origin is the origin.
    private func refreshPlacement() {
        let surfaces = NSScreen.screens.map { screen -> ScreenSurface in
            let depth = screen.safeAreaInsets.top
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = screen.frame.width - left - right
            return ScreenSurface(
                frame: screen.frame,
                notch: depth > 0 && width > 0
                    ? CGRect(
                        x: screen.frame.minX + left,
                        y: screen.frame.maxY - depth,
                        width: width,
                        height: depth
                    )
                    : nil,
                isMain: screen.frame.origin == .zero
            )
        }

        host.screensDidChange(to: surfaces)
        guard let layout = host.layout else { return }
        glanceWindow.setFrame(layout.glance, display: true)
        if host.isPanelOpen {
            panelWindow.setFrame(layout.panel, display: true)
        }
    }
}

/// The Glance's window: it draws a figure and takes a click, and never takes the key window with it.
final class GlanceWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The Panel's window. A borderless window cannot become key by default and the Panel must: Esc and
/// ⌘, are answered here, while it has focus, and nowhere else in an app with no menu bar.
final class PanelWindow: NSPanel {
    var onDismiss: (() -> Void)?
    var onSettings: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc. A view that wants it — a text field cancelling its edit — gets first refusal, and what is
    /// left over comes here, which for a Panel holding figures and one menu is the Panel itself.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// ⌘, and ⌘Q while the Panel has focus (#19), answered on the window because the app is an
    /// accessory with no menu bar on screen to answer them: SwiftUI installs the key equivalents into
    /// `mainMenu`, which nobody sees and — with the app inactive, which is the whole point of a notch
    /// instrument — no key equivalent reaches.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers
        else { return super.performKeyEquivalent(with: event) }

        switch key {
        case ",":
            onSettings?()
            return true
        case "q":
            NSApplication.shared.terminate(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// The Glance's content view: it takes the mouse, so the Glance's two gestures are AppKit's and the
/// SwiftUI inside it only renders. That is also why a hover can read nothing — this view does not ask
/// for the cursor and no tracking area exists anywhere in the app, which `NotchHostTests` keeps true.
final class GlanceSurface: NSView {
    var onClick: (() -> Void)?
    var onRightClick: ((NSPoint) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: nil)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event.locationInWindow)
    }
}
