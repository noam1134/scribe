import Foundation
import Testing
@testable import ScribeCore

struct TextDirectionTests {
    @Test(arguments: [
        ("לקנות חלב", TextDirection.rightToLeft),
        ("Buy milk", .leftToRight),
        ("4821 קוד לדלת", .rightToLeft),
        ("🧪 Smoke test", .leftToRight),
        ("📌 לקנות", .rightToLeft),
        ("", .leftToRight),
        ("12:30", .leftToRight),
        ("buy חלב", .leftToRight),
    ] as [(String, TextDirection)])
    func firstStrongLetterDecides(text: String, expected: TextDirection) {
        #expect(TextDirection.of(text) == expected)
    }
}
