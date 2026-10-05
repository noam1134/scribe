import Foundation
import Testing
@testable import ScribeCore

struct PanelPlacementTests {
    typealias Rect = PanelPlacement.Rect
    typealias Point = PanelPlacement.Point

    /// A laptop screen with a menu bar, and a bigger display to its right
    /// (AppKit coordinates: origin bottom-left, y up).
    let laptop = PanelPlacement.Screen(
        frame: Rect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: Rect(x: 0, y: 0, width: 1512, height: 949)
    )
    let display = PanelPlacement.Screen(
        frame: Rect(x: 1512, y: -200, width: 2560, height: 1440),
        visibleFrame: Rect(x: 1512, y: -200, width: 2560, height: 1415)
    )

    func origin(_ mouse: Point, screens: [PanelPlacement.Screen]? = nil) -> Point? {
        PanelPlacement.origin(width: 600, height: 160, mouse: mouse, screens: screens ?? [laptop, display])
    }

    @Test func opensOnTheScreenUnderThePointer() throws {
        let origin = try #require(origin(Point(x: 2000, y: 300)))
        #expect(origin.x == 1512 + (2560 - 600) / 2)
        // Top edge a fifth of the way down the visible area.
        #expect(origin.y + 160 == 1215 - 1415 * 0.2)
    }

    @Test func thePointerOnTheMenuBarStillCounts() throws {
        #expect(try #require(origin(Point(x: 100, y: 982))).x == (1512 - 600) / 2)
    }

    @Test func aPointerOffEveryScreenUsesTheFirst() throws {
        #expect(try #require(origin(Point(x: -500, y: -500))).x == (1512 - 600) / 2)
    }

    @Test func staysInsideASmallScreen() {
        let tiny = PanelPlacement.Screen(frame: Rect(x: 0, y: 0, width: 500, height: 150), visibleFrame: Rect(x: 0, y: 0, width: 500, height: 140))
        #expect(origin(Point(x: 0, y: 0), screens: [tiny]) == Point(x: 0, y: 0))
    }

    @Test func noScreensNoOrigin() {
        #expect(origin(Point(x: 0, y: 0), screens: []) == nil)
    }
}
