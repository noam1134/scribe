import Testing
@testable import ScribeCore

struct CategoryPaletteTests {
    @Test func suggestsTheFirstUnusedColor() {
        #expect(CategoryPalette.suggestedColorName(avoiding: []) == "red")
        #expect(CategoryPalette.suggestedColorName(avoiding: ["red", "yellow"]) == "orange")
        #expect(CategoryPalette.suggestedColorName(avoiding: ["blue", "blue"]) == "red")
    }

    @Test func cyclesOnceEveryColorIsUsed() {
        let all = CategoryPalette.colorNames
        #expect(CategoryPalette.suggestedColorName(avoiding: all) == all[0])
        #expect(CategoryPalette.suggestedColorName(avoiding: all + ["red"]) == all[1])
    }

    @Test func suggestionsAreValidColors() {
        for used in 0...30 {
            let names = Array(repeating: "red", count: used)
            #expect(CategoryPalette.colorNames.contains(CategoryPalette.suggestedColorName(avoiding: names)))
        }
    }
}
