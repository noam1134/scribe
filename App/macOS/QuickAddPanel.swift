import AppKit
import ScribeCore
import SwiftUI

/// The ⌃⌥Space panel (spec §8, §9.3): a floating glass composer, Spotlight
/// style, on the display under the pointer. Return adds and closes; Esc or
/// clicking elsewhere closes. The app is activated so the first click
/// works, and the app that was in front gets activation back on close.
@MainActor
final class QuickAddPanelController {
    static let width: CGFloat = 620

    private let loader: StoreLoader
    private var panel: QuickAddPanel?
    private var escapeMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(loader: StoreLoader) {
        self.loader = loader
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() {
        if isShown { close(returningFocus: true) } else { show() }
    }

    func show() {
        if case .loading = loader.state { loader.load() }
        guard case .ready(let store) = loader.state else {
            // The window explains a store that won't open (spec §13).
            NSApp.activate()
            return
        }
        previousApp = NSApp.isActive ? nil : NSWorkspace.shared.frontmostApplication

        let panel = self.panel ?? QuickAddPanel()
        self.panel = panel
        panel.onResignKey = { [weak self] in self?.close(returningFocus: false) }
        let content = QuickAddPanelView(
            store: store,
            close: { [weak self] in self?.close(returningFocus: true) },
            resize: { [weak panel] height in panel?.setHeightKeepingTop(height) }
        )
        let host = FirstMouseHostingView(rootView: content)
        host.sizingOptions = []
        panel.contentView = host
        panel.place(width: Self.width, height: 130)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // SwiftUI's focus state doesn't reach a hand-made window before it
        // is key; put the caret in the field once the content is laid out.
        DispatchQueue.main.async { panel.focusTextField() }
        installEscapeMonitor(for: panel)
        MacLog.hotkey.info("Quick-add panel shown")
    }

    func close(returningFocus: Bool) {
        guard let panel, panel.isVisible else { return }
        removeEscapeMonitor()
        panel.onResignKey = nil
        panel.orderOut(nil)
        panel.contentView = nil
        if returningFocus, let previousApp, !previousApp.isTerminated {
            previousApp.activate(from: .current, options: [])
        }
        previousApp = nil
    }

    /// Esc arrives as a key-down with key code 53: `.onExitCommand` never
    /// fires in a borderless panel, and the text field's field editor would
    /// otherwise take it (spec §9.3).
    private func installEscapeMonitor(for panel: QuickAddPanel) {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard event.keyCode == 53, let panel, event.window === panel else { return event }
            MainActor.assumeIsolated { self?.close(returningFocus: true) }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}

/// Borderless, transparent, floating on every Space; the SwiftUI content
/// draws the glass. Non-activating, so it takes the keyboard even before
/// (or if macOS declines) the app's activation.
final class QuickAddPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: QuickAddPanelController.width, height: 130),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    func focusTextField() {
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(field(in:)).first
        }
        if let field = contentView.flatMap(field(in:)) { makeFirstResponder(field) }
    }

    /// Opens on the screen under the pointer (spec §9.3).
    func place(width: CGFloat, height: CGFloat) {
        let screens = NSScreen.screens.map { PanelPlacement.Screen(frame: $0.frame.placementRect, visibleFrame: $0.visibleFrame.placementRect) }
        let mouse = NSEvent.mouseLocation
        let origin = PanelPlacement.origin(
            width: width,
            height: height,
            mouse: PanelPlacement.Point(x: mouse.x, y: mouse.y),
            screens: screens
        )
        let point = origin.map { NSPoint(x: $0.x.rounded(), y: $0.y.rounded()) } ?? .zero
        setFrame(NSRect(origin: point, size: NSSize(width: width, height: height)), display: false)
    }

    /// The content reports its height; grow or shrink downward from the top.
    func setHeightKeepingTop(_ height: CGFloat) {
        // Whole points: a fractional size that never matches the window's
        // frame sends SwiftUI and AppKit into a layout loop on macOS 27.
        let height = height.rounded(.up)
        guard height > 0, abs(frame.height - height) >= 1 else { return }
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - height, width: frame.width, height: height), display: true)
        invalidateShadow()
    }
}

/// Takes the click that activates the app, so the first click lands.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSRect {
    var placementRect: PanelPlacement.Rect {
        PanelPlacement.Rect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}

private struct QuickAddPanelView: View {
    let store: any ItemStore
    let close: () -> Void
    let resize: (CGFloat) -> Void

    private enum Field: Hashable { case text }

    @State private var composer: QuickAddComposer
    @State private var error: String?
    @FocusState private var focus: Field?

    init(store: any ItemStore, close: @escaping () -> Void, resize: @escaping (CGFloat) -> Void) {
        self.store = store
        self.close = close
        self.resize = resize
        _composer = State(initialValue: QuickAddComposer(store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacComposer(
                store: store,
                composer: composer,
                focus: $focus,
                focusValue: .text,
                font: .title2,
                perform: perform
            ) { _ in close() }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(width: QuickAddPanelController.width, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focus = .text }
        .onChange(of: composer.text) { error = nil }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
