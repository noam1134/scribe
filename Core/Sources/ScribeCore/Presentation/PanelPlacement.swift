import Foundation

/// Where the Mac quick-add panel opens (spec §9.3): on the display under the
/// pointer, centered, its top a fifth of the way down — about where
/// Spotlight sits. AppKit coordinates (origin bottom-left, y up). Plain
/// doubles: Core doesn't import CoreGraphics.
public enum PanelPlacement {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var maxX: Double { x + width }
        var maxY: Double { y + height }

        /// Inclusive on every edge: the pointer can sit on a screen's top row.
        func contains(_ point: Point) -> Bool {
            point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
        }
    }

    public struct Screen: Equatable, Sendable {
        public var frame: Rect
        /// The frame without the menu bar and Dock.
        public var visibleFrame: Rect

        public init(frame: Rect, visibleFrame: Rect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// The panel's bottom-left corner, kept inside the visible area; nil
    /// when there is no screen. A pointer off every screen uses the first.
    public static func origin(width: Double, height: Double, mouse: Point, screens: [Screen]) -> Point? {
        guard let screen = screens.first(where: { $0.frame.contains(mouse) }) ?? screens.first else { return nil }
        let area = screen.visibleFrame
        let x = area.x + (area.width - width) / 2
        let y = area.maxY - area.height * 0.2 - height
        return Point(
            x: max(min(x, area.maxX - width), area.x),
            y: max(min(y, area.maxY - height), area.y)
        )
    }
}
