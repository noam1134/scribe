import AppKit
import ScribeCore
import SwiftUI

/// The ⌃⇧Space panel (spec §8, §9.3; the shortcut is amended from
/// ⌃⌥Space): a floating glass composer, Spotlight style, on the display
/// under the pointer. Return adds and closes; Esc or clicking elsewhere
/// closes. Like Spotlight it never activates Scribe — the app in front
/// stays in front — yet it takes the keyboard and the first click.
@MainActor
final class QuickAddPanelController {
    static let width: CGFloat = 620

    private let loader: StoreLoader
    private var panel: QuickAddPanel?
    private var escapeMonitor: Any?

    init(loader: StoreLoader) {
        self.loader = loader
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() {
        if isShown { close() } else { show() }
    }

    func show() {
        if case .loading = loader.state { loader.load() }
        let panel = self.panel ?? QuickAddPanel()
        self.panel = panel
        panel.onResignKey = { [weak self] in self?.close() }
        let close: () -> Void = { [weak self] in self?.close() }
        let resize: (CGFloat) -> Void = { [weak panel] height in panel?.setHeightKeepingTop(height) }
        if case .ready(let store) = loader.state {
            panel.contentView = FirstMouseHostingView.make(PanelChrome(resize: resize) {
                QuickAddPanelView(store: store, close: close)
            })
        } else {
            // Say so instead of failing silently; the window has Retry (spec §13).
            MacLog.hotkey.error("Quick-add panel: the store isn't open")
            panel.contentView = FirstMouseHostingView.make(PanelChrome(resize: resize) {
                StoreProblemView { [weak self] in
                    self?.close()
                    self?.openMainWindow()
                }
            })
        }
        panel.place(width: Self.width, height: 130)

        // A non-activating panel becomes key without activating Scribe.
        panel.makeKeyAndOrderFront(nil)
        // SwiftUI's focus state doesn't reach a hand-made window before it
        // is key; put the caret in the field once the content is laid out.
        DispatchQueue.main.async { panel.focusTextField() }
        installEscapeMonitor(for: panel)
        MacLog.hotkey.info("Quick-add panel shown")
    }

    /// Orders the panel out. Its content stays until the next `show()`
    /// replaces it: Return closes the panel while the field is still
    /// handling that key.
    func close() {
        guard let panel, panel.isVisible else { return }
        removeEscapeMonitor()
        panel.onResignKey = nil
        panel.orderOut(nil)
    }

    /// "Open Scribe" from the store-problem panel: the window shows the
    /// error and Retry. With every window closed, a pending link makes the
    /// menu bar open one.
    private func openMainWindow() {
        NSApp.activate()
        if !MacWindows.bringMainForward() { loader.pendingLink = .upcoming }
    }

    /// Esc arrives as a key-down with key code 53: `.onExitCommand` never
    /// fires in a borderless panel, and the text field's field editor would
    /// otherwise take it (spec §9.3).
    private func installEscapeMonitor(for panel: QuickAddPanel) {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard event.keyCode == 53, let panel, event.window === panel else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}

/// Borderless, transparent, floating on every Space; the SwiftUI content
/// draws the glass. Non-activating: it becomes key while another app stays
/// active.
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

/// Takes the first click even though Scribe isn't the active app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// The panel sizes itself from the content's reported height.
    static func make(_ rootView: Content) -> FirstMouseHostingView {
        let view = FirstMouseHostingView(rootView: rootView)
        view.sizingOptions = []
        return view
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSRect {
    var placementRect: PanelPlacement.Rect {
        PanelPlacement.Rect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}

/// The panel's glass, at its width; reports its height so the window fits.
private struct PanelChrome<Content: View>: View {
    let resize: (CGFloat) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(width: QuickAddPanelController.width, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resize($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Shown instead of the composer when the store couldn't be opened.
private struct StoreProblemView: View {
    let openScribe: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scribe can’t open your notes").font(.headline)
                    Text("Nothing was deleted. Open Scribe to try again.")
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Spacer(minLength: 8)
            Button("Open Scribe", action: openScribe)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

private struct QuickAddPanelView: View {
    let store: any ItemStore
    let close: () -> Void

    private enum Field: Hashable { case text }

    @State private var composer: QuickAddComposer
    @State private var error: String?
    @FocusState private var focus: Field?

    init(store: any ItemStore, close: @escaping () -> Void) {
        self.store = store
        self.close = close
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
