import AppKit
import Combine
import SwiftUI

/// The one window the notch host draws: a borderless, non-activating panel that is the Glance while the
/// Panel is shut, and the Glance grown into the Panel while it is open (#19, #21, #22).
///
/// Nothing here decides *where* anything goes, *how long* the shape takes, or *when* a read happens —
/// `NotchHost` and `NotchGeometry` do, from the screens this type hands them and the gestures it
/// forwards. What is left in AppKit is translation: a placement becomes a `setFrame`, an opening becomes
/// a resize, a right-click becomes a menu.
///
/// The window does not activate the app, because the instrument is something the Operator glances at
/// while working in another application: clicking it must not bring Sprint Pulse forward or take the
/// keyboard away. It takes key status only while the Panel is open, and only so that Esc, ⌘, and ⌘Q
/// reach it — a surface that cannot be typed into has no business holding the key window once it is just
/// a band again, which is what `settle` arranges.
///
/// ### How one window is still two surfaces
///
/// `NotchSurface` holds three layers: the black silhouette, which is the window's own size and so *is*
/// the morph; the band's figure, pinned to the top strip; and the Panel's reading, at its measured size
/// and pinned just below the band. Growing the window reveals the reading from the top down; it never
/// moves, because nothing about it is asked to fit the window's current height. That is AC 1's "nothing
/// else on the Panel moves", and it is why the reading's layer is sized from `fittingSize` rather than
/// from the window's bounds.
///
/// ### Why the shape is allowed to move at all
///
/// ADR-0007 retired ADR-0006's reservation of motion for M3. What is left is *structural* motion — the
/// same short grow-and-shrink every time, carrying nothing about the reading. `host.morphDuration` is the
/// one question asked per gesture (`0` for Reduce Motion or the Operator's own "no animation" switch),
/// and the read itself is issued on the click in `NotchHost` and never here — which is what
/// `SourceGuardTests` keeps true rather than what it trusts.
///
/// `animationBehavior = .none` stays, and not for the reason it was written: not because nothing moves,
/// but because the morph is this app's own — stepped frame by frame from `host.morphDuration`, since
/// AppKit's window animation does not run for a borderless panel like this one. Letting the system
/// animate too would lay a second motion over the one that is measured, short, and identical every time.
@MainActor
final class NotchWindow: NSObject {
    private let panel: PanelModel
    private let host: NotchHost

    private let window = SurfacePanel(
        contentRect: CGRect(origin: .zero, size: NotchMetrics.nominalBandSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private lazy var surface = NotchSurface(
        glanceView: GlanceView(panel: panel, host: host, press: { [weak self] in self?.togglePanel() }),
        panelView: PanelView(panel: panel)
    )

    /// The click the Glance took this cycle. A key-window change can *follow* that same click — one
    /// gesture seen twice, once as the gesture and once as the window's focus moving — and the click
    /// knows what the Operator meant. A dismissal arriving in the same cycle is therefore dropped:
    /// without this, the click that opens the Panel could be answered by the loss its own focus change
    /// posted, and the Panel would shut again on the way in (#19 AC 2, #22 AC 5).
    private var glanceIsBeingClicked = false

    /// The current leg of the morph: where it started, where it is going, and the two instants that
    /// bound it, in `systemUptime`. `legEndsAt == nil` is the window standing still.
    private var legFrom = CGRect.zero
    private var legTo = CGRect.zero
    private var legStartsAt: TimeInterval = 0
    private var legEndsAt: TimeInterval?
    private var morphTimer: Timer?

    private var screenObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var contentCancellable: AnyCancellable?

    init(panel: PanelModel, host: NotchHost) {
        self.panel = panel
        self.host = host
        super.init()

        configure()
    }

    /// Draws the Glance and starts following the screens. Called once, from the composition root.
    ///
    /// That launch issues no read is not this method's doing — `PanelModel` withholds the live fetch
    /// and `NotchHost` issues it only on a click (invariant 14). What is decided here is only that the
    /// Panel is not on screen until the Operator puts it there.
    func start() {
        refreshPlacement()
        window.orderFrontRegardless()

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
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.glanceIsBeingClicked else { return }
                self.dismissPanel()
            }
        }

        // Best effort beside it: a click in an application that never had the Panel's key status to
        // lose. A global monitor delivers nothing without the input permission this app does not ask
        // for, so the loss above is what closing on an outside click really rests on.
        //
        // Clicks inside Sprint Pulse's own window never reach either. Since #22 that surface is the
        // whole silhouette rather than the reading's column, so on a cutout wide enough to make the
        // band wider than the Panel's 280 the black margin beside the reading belongs to the window
        // and a click there does not close the Panel — the same answer as a click on the reading's own
        // background, and the shape the Operator clicked is the shape that is on screen.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor in self?.dismissPanel() }
        }

        // The Panel's height is its content's: a reading arriving, or an Unmapped Status being
        // resolved, changes how many rows there are — and since #22, how tall the window is.
        contentCancellable = panel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refitPanel() }
        }
    }

    // MARK: - Building the window

    private func configure() {
        window.contentView = surface
        window.isExcludedFromWindowsMenu = true

        // The band is hardware flush with the top edge of the screen, and hardware casts no shadow: a
        // shadow around it is exactly what would read as a window parked on the notch (#25). The
        // Panel's shadow belongs to the expanded shape only, so `settle` turns it on and off with the
        // morph rather than the window carrying one all day.
        window.hasShadow = false

        surface.band.onClick = { [weak self] in self?.togglePanel() }
        surface.band.onRightClick = { [weak self] point in self?.popContextMenu(at: point) }
        window.onDismiss = { [weak self] in self?.dismissPanel() }
        window.onSettings = { [weak self] in self?.host.openSettings() }

        // Above the menu bar, on every Space, still there when the app is not the active one, never
        // animated by the system, and in the dark scheme whatever the system appearance says.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        // ADR-0007: the surface is black, and a black surface with light content is unreadable, so the
        // scheme is forced rather than followed. It is forced on the *window* because that is the one
        // thing the whole content hangs from: the SwiftUI subtree resolves its semantic colours through
        // the hosting view's effective appearance, and the controls SwiftUI puts inside it — the
        // pull-down that picks a Flow State for an unmapped status, the one that names the sprint —
        // resolve theirs through the same window when they pop their menus. A `colorScheme` environment
        // value would style the first and leave the second to the desktop. Settings is untouched on
        // purpose: it is an ordinary window that follows the system appearance (#21 AC 4).
        window.appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Gestures

    /// The click, and VoiceOver's press action, which arrives here too (#22 AC 6). One gesture decides
    /// both states of the Panel, so the Glance needs no second control to close it.
    private func togglePanel() {
        glanceIsBeingClicked = true
        // The read is issued inside this call, on the click, and not at the end of the morph below it
        // (invariant 14, #22 AC 2).
        host.glanceWasClicked()
        if host.isPanelOpen {
            openPanel()
        } else {
            closePanel()
        }
        // Cleared on the next turn of the run loop, which is where the observers' `Task`s land —
        // the loss posted while this method ran is queued behind that clear and so is skipped.
        DispatchQueue.main.async { [weak self] in self?.glanceIsBeingClicked = false }
    }

    /// The shape grows downward from the band.
    ///
    /// The reading is measured *first*, as the two-window host did: the window's height is the
    /// reading's, and on a fresh launch the only figure so far is `defaultPanelSize`'s guess. Growing
    /// to the guess and then bending the leg when the click's own read lands would make the first open
    /// the one that is not identical to every other (#22 AC 1).
    ///
    /// The reading's layer is put on screen before the grow so the morph reveals it — a Panel that
    /// appeared only once the shape had stopped moving would be the second window this ticket retires,
    /// arriving one frame late. The shadow is not: it joins at the arrival, because for the first 220ms
    /// of the grow the shape still includes the band, and hardware casts no shadow (#25).
    private func openPanel() {
        measureReading()
        guard let layout = host.layout else { return }
        surface.apply(layout)
        surface.reading.isHidden = false
        window.makeKeyAndOrderFront(nil)
        morph(to: layout.windowOpen, .gesture)
    }

    /// The same morph backwards: the shape shrinks back to the band, and nothing is asked of the Board.
    private func closePanel() {
        guard let layout = host.layout else { return }
        morph(to: layout.windowClosed, .gesture)
    }

    /// Idempotent by design: the key-window loss and the global monitor can both describe one click
    /// outside, and a dismissal must not read the Board twice over.
    private func dismissPanel() {
        guard host.isPanelOpen else { return }
        host.panelWasDismissed()
        closePanel()
    }

    /// The Panel hangs from the notch's bottom edge, so a content change keeps that edge and moves only
    /// the bottom.
    private func refitPanel() {
        measureReading()
        guard host.isPanelOpen, let layout = host.layout else { return }
        // A reading that lands mid-morph retargets the shape already moving, finishing inside the clock
        // the click started rather than starting a second one the Operator would see as a stutter; one
        // that lands while the Panel stands open just makes it taller, as it did before #22.
        morph(to: layout.windowOpen, .retarget)
    }

    /// The reading's own height, forced out of the layout engine and reported to the host so the
    /// geometry can place it. The subtree is laid out before the size is read because a model change
    /// and the redraw it causes are not the same turn of the run loop, and a stale height would leave
    /// the last row cut off.
    private func measureReading() {
        surface.reading.layoutSubtreeIfNeeded()
        let size = surface.reading.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        host.panelContentSizeChanged(size)
        if let layout = host.layout {
            surface.apply(layout)
        }
    }

    // MARK: - The morph

    /// What moved the window, which is the only thing that decides how long the move takes.
    private enum Morph {
        /// The Operator opened or closed the Panel: a fresh morph, over `host.morphDuration`.
        case gesture
        /// The shape's target moved while a morph was running: finish on the clock already started,
        /// and move instantly if none is.
        case retarget
        /// The screens changed: the window goes where the new ones say, instantly.
        case placement
    }

    /// Moves the one window to `frame`, stepping the shape's own bottom edge over the clock the gesture
    /// started.
    ///
    /// The frames are stepped here rather than handed to AppKit's window animation because that
    /// animation does not run for this window: `animator().setFrame(_:display:)` left it at the band's
    /// size, and `setFrame(_:display:animate:)` jumped straight to the target with and without
    /// `animationBehavior` set — both measured on macOS 26 while writing this. A timer is also what
    /// makes the retarget below possible, since the shape's current position is the only honest starting
    /// point for a leg that begins mid-morph.
    ///
    /// The deadline is carried across a retarget rather than restarted because ADR-0007's claim is that
    /// the motion is *short and identical every time* — a reading arriving 100ms into the grow must not
    /// turn a 220ms morph into a 440ms one. `host.morphDuration` answers `0` for Reduce Motion and for
    /// the "no animation" preference, and the instant path is the same code either way: the difference
    /// between an instant open and an animated one is a duration, not a second path to keep in step.
    private func morph(to frame: CGRect, _ kind: Morph) {
        let now = ProcessInfo.processInfo.systemUptime
        let duration = host.morphDuration
        let deadline: TimeInterval? = switch kind {
        case .gesture where duration > 0: now + duration
        case .retarget: legEndsAt
        case .gesture, .placement: nil
        }

        guard let deadline, deadline > now else {
            stopMorph()
            window.setFrame(frame, display: true)
            settle()
            return
        }

        legFrom = window.frame
        legTo = frame
        legStartsAt = now
        legEndsAt = deadline
        startMorph()
    }

    /// One step of the morph: the shape at its eased position along the current leg, and the arrival
    /// when the clock runs out.
    private func stepMorph() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let endsAt = legEndsAt else {
            stopMorph()
            return
        }
        let remaining = endsAt - now
        guard remaining > 0 else {
            window.setFrame(legTo, display: true)
            stopMorph()
            settle()
            return
        }
        let total = max(endsAt - legStartsAt, 0.001)
        let t = 1 - remaining / total
        window.setFrame(legFrom.lerped(to: legTo, by: t * t * (3 - 2 * t)), display: true)
    }

    private func startMorph() {
        guard morphTimer == nil else { return }
        // `.common`, so the shape keeps moving while a menu the Panel hosts is open rather than freezing
        // half-grown at the moment the Operator is most likely to be looking at it.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepMorph()
        }
        RunLoop.main.add(timer, forMode: .common)
        morphTimer = timer
    }

    private func stopMorph() {
        morphTimer?.invalidate()
        morphTimer = nil
        legEndsAt = nil
    }

    /// Brings the window's ornament in line with the state the host is in, whichever morph just landed:
    /// the reading and the shadow belong to the expanded shape only (#25 — hardware casts no shadow),
    /// and a window that is only a band must not be holding the keyboard.
    ///
    /// Derived from the host's state rather than passed in per morph, because a gesture that interrupts
    /// another leaves the interrupted one with nothing to arrive at: the timer always runs toward the
    /// newest target, and the newest target settles the window.
    private func settle() {
        let open = host.isPanelOpen
        surface.reading.isHidden = !open
        window.hasShadow = open
        if !open {
            dropKeyStatus()
        }
    }

    /// An ordered-out window cannot be key, and `orderFrontRegardless` puts the band straight back
    /// without taking the key window for it — both in the same turn of the run loop, so the screen is
    /// flushed once between them. The alternative was a second window to hand the keyboard to, which is
    /// the arrangement #22 retires.
    private func dropKeyStatus() {
        guard window.isKeyWindow else { return }
        window.orderOut(nil)
        window.orderFrontRegardless()
    }

    // MARK: - The band's context menu

    /// Right-click: the two ways out of an app with no menu bar and no Dock icon — Settings… and Quit
    /// (#19).
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

        menu.popUp(
            positioning: nil,
            at: surface.band.convert(point, from: nil),
            in: surface.band
        )
    }

    @objc private func openSettingsFromMenu() {
        host.openSettings()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Screens

    /// The screens as the placement decision needs them, read straight off `NSScreen`, and the window
    /// moved to wherever that says it belongs.
    ///
    /// The notch's own rect is the strip across the top of a screen that the menu bar cannot use:
    /// `safeAreaInsets.top` is its depth, and its width is what the screen's width loses to
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` — the two unobstructed rects either side of
    /// it. On this Mac that measures 185×32. A screen with no obstruction reports a zero inset, and
    /// `NotchGeometry` draws the band at its top-centre instead, where a notch would be.
    ///
    /// `isMain` is asked of the coordinate space rather than of `NSScreen.main`, which reports the
    /// screen with the keyboard focus: the main display is the one whose origin is the origin of the
    /// global Cocoa space.
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
        surface.apply(layout)
        morph(
            to: host.isPanelOpen ? layout.windowOpen : layout.windowClosed,
            .placement
        )
    }
}

/// The notch host's window. A borderless window cannot become key by default and the Panel must: Esc and
/// ⌘, are answered here, while it has focus, and nowhere else in an app with no menu bar. While the
/// Panel is shut the window asks not to be key at all (`NotchWindow.settle`), because the band is a
/// surface nothing can be typed into.
final class SurfacePanel: NSPanel {
    var onDismiss: (() -> Void)?
    var onSettings: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc. A view that wants it — a text field cancelling its edit — gets first refusal, and what is
    /// left over comes here, which for a Panel holding figures and one menu is the Panel itself.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// ⌘, and Q while the Panel has focus (#19), answered on the window because the app is an
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

/// The window's content: its one silhouette, the band's figure across the top of it, and the Panel's
/// reading below — three layers that differ only in size, which is what lets one window's resize read
/// as one shape growing (#22 AC 1).
///
/// The reading's layer keeps its measured size and is pinned just under the band, so a window halfway
/// through growing shows the top of a reading that is not yet finished being revealed. Nothing is asked
/// to fit the window's current height, so nothing has room to move while it changes: the clip is the
/// window's own bounds, and the only thing that travels is the bottom edge of the silhouette.
@MainActor
final class NotchSurface: NSView {
    /// The band's click strip, spanning the window's top edge.
    let band: BandSurface
    /// The Panel's reading, at the size its content reported.
    let reading: NSHostingView<PanelView>

    private let silhouette: NSHostingView<NotchSilhouette>
    private let glance: NSHostingView<GlanceView>

    /// The band's height — the cutout's own depth — which is also the window's whole height while the
    /// Panel is shut.
    private var bandHeight: CGFloat {
        didSet { layoutLayers() }
    }

    /// The reading's measured size, which decides how far down the window has to go to hold it.
    private var readingSize: CGSize {
        didSet { layoutLayers() }
    }

    /// Places the layers from the geometry's answer for the screens there are now. Both measurements
    /// come from one `NotchLayout` and travel together, so this is the only way in: handed separately
    /// they could disagree, and the disagreement would be the join the reading hangs from.
    func apply(_ layout: NotchLayout) {
        bandHeight = layout.glance.height
        readingSize = layout.panel.size
    }

    init(glanceView: GlanceView, panelView: PanelView) {
        bandHeight = NotchMetrics.nominalBandSize.height
        readingSize = NotchMetrics.defaultPanelSize
        band = BandSurface(frame: .zero)
        silhouette = NSHostingView(rootView: NotchSilhouette())
        glance = NSHostingView(rootView: glanceView)
        reading = NSHostingView(rootView: panelView)
        super.init(frame: CGRect(origin: .zero, size: NotchMetrics.nominalBandSize))

        // The silhouette and the band's figure are sized by this view, so neither may hold itself to the
        // size its SwiftUI content first reported: a hosting view that sizes to its content ignores the
        // frame it is handed, and the black would stay 32pt tall inside a 372pt window — the reading
        // sitting on the desktop instead of on the hardware, which is what the first on-screen check of
        // this found. The reading keeps its default sizing options because `refitPanel` asks it for a
        // `fittingSize`, and that answer is only the content's own height while the view is still
        // measuring itself against the content.
        silhouette.sizingOptions = []
        glance.sizingOptions = []

        // The silhouette is the window's size at every frame of the morph; the band keeps its height and
        // rides the top edge; the reading keeps both its dimensions and rides the top edge too, so the
        // grow reveals it from the top down rather than stretching it. `layoutLayers` agrees with these
        // masks and runs on every resize; they are here so a resize that bypasses it still holds the
        // join.
        silhouette.autoresizingMask = [.width, .height]
        band.autoresizingMask = [.width, .minYMargin]
        reading.autoresizingMask = [.minYMargin]
        reading.isHidden = true

        addSubview(silhouette)
        addSubview(reading)
        addSubview(band)
        band.addSubview(glance)

        // The reading is taller than the window for as long as the shape is growing, and AppKit does not
        // clip a layer-backed subview to its parent: without this the rows below the window's own bottom
        // edge drew themselves onto the desktop with no black behind them, which is the failure the first
        // screenshot of the morph caught. The window's bounds are the clip the reveal depends on, so the
        // view that carries them says so.
        wantsLayer = true
        layer?.masksToBounds = true

        layoutLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayers()
    }

    /// Every layer's frame, from the bounds this view has right now.
    ///
    /// Called from `setFrameSize` and from the two measurements' setters rather than left to
    /// `layout()`: the morph moves the window from AppKit's animation, and a layout pass on a plain
    /// borderless panel's view is not something that can be counted on to arrive — the first version of
    /// this relied on it and drew a band that never grew.
    private func layoutLayers() {
        // Cocoa coordinates, origin at the window's bottom-left: the band is against the top edge, and
        // the reading hangs from the band — which while the Panel is shut puts it below this view's own
        // bounds, where the window clips it away.
        silhouette.frame = bounds
        band.frame = CGRect(x: 0, y: bounds.height - bandHeight, width: bounds.width, height: bandHeight)
        glance.frame = band.bounds
        reading.frame = CGRect(
            x: (bounds.width - readingSize.width) / 2,
            y: bounds.height - bandHeight - readingSize.height,
            width: readingSize.width,
            height: readingSize.height
        )
    }
}

/// The band's own strip of the window: it takes the mouse, so the Glance's two gestures are AppKit's and
/// the SwiftUI inside it only renders. That is also why a hover can read nothing — this view does not ask
/// for the cursor and no tracking area exists anywhere in the app, which `NotchHostTests` keeps true.
///
/// It spans the window's full width and the cutout's depth, and it stays there while the Panel is open:
/// the second click that closes the Panel lands on the same strip the first click opened it from, which
/// is what makes the Glance one control with two states (#22 AC 5).
final class BandSurface: NSView {
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

private extension CGRect {
    /// This rect's four edges travelled toward `other`'s, `t` of the way there.
    ///
    /// Every edge is interpolated although #22's morph only ever moves the bottom one:
    /// `NotchGeometry` keeps the column's x, width and top edge the same between its two frames and
    /// `NotchGeometryTests` pins that, so stepping the bottom alone would bake a geometry promise into
    /// the window layer — and a future change there would move half a shape instead of all of it.
    func lerped(to other: CGRect, by t: CGFloat) -> CGRect {
        CGRect(
            x: minX + (other.minX - minX) * t,
            y: minY + (other.minY - minY) * t,
            width: width + (other.width - width) * t,
            height: height + (other.height - height) * t
        )
    }
}
