import Foundation
import Testing
@testable import ScribeCore

/// Plain-language quick-add: leading request phrases leave the title.
struct RequestPhrasesTests {
    typealias F = ParserFixture

    static let englishCases: [(String, String)] = [
        ("remind me to call mom", "Call mom"),
        ("Remind me to call mom", "Call mom"),
        ("remind me call mom", "Call mom"),
        ("remind me about the dentist", "The dentist"),
        ("remember to buy milk", "Buy milk"),
        ("don't forget to pay rent", "Pay rent"),
        ("Don\u{2019}t forget to pay rent", "Pay rent"),
        ("do not forget to pay rent", "Pay rent"),
        ("I need to renew my passport", "Renew my passport"),
        ("I have to renew my passport", "Renew my passport"),
        ("todo: fix the bike", "Fix the bike"),
        ("TODO: fix the bike", "Fix the bike"),
        ("please call Dan", "Call Dan"),
        ("please, remind me to call Dan", "Call Dan"),
        ("add a task to call Dan", "Call Dan"),
        ("add reminder: call Dan", "Call Dan"),
        ("add a reminder to call Dan", "Call Dan"),
        ("remind me to iPhone backup", "iPhone backup"),
        ("remind me to Call Dan", "Call Dan"),
    ]

    @Test(arguments: englishCases)
    func englishPhrasesLeaveTheTitle(text: String, title: String) {
        #expect(F.parse(text).title == title)
    }

    static let hebrewCases: [(String, String)] = [
        ("תזכיר לי לקנות חלב", "לקנות חלב"),
        ("תזכירי לי לקנות חלב", "לקנות חלב"),
        ("להזכיר לי להתקשר לדני", "להתקשר לדני"),
        ("לא לשכוח לשלם חשבון חשמל", "לשלם חשבון חשמל"),
        ("אל תשכח לשלם חשבון חשמל", "לשלם חשבון חשמל"),
        ("צריך לקנות חלב", "לקנות חלב"),
        ("אני צריך לקנות חלב", "לקנות חלב"),
        ("אני צריכה לקנות חלב", "לקנות חלב"),
        ("בבקשה תזכיר לי לקנות חלב", "לקנות חלב"),
        // The ש that opens a clause goes; a word's own ש stays.
        ("תזכיר לי שאני צריך לקנות חלב", "לקנות חלב"),
        ("תזכיר לי שצריך לקנות חלב", "לקנות חלב"),
        ("תזכיר לי שהפגישה זזה", "הפגישה זזה"),
        ("תזכיר לי ש-הדוח מוכן", "הדוח מוכן"),
        ("תזכיר לי שולחן חדש", "שולחן חדש"),
        ("לא לשכוח - לקנות חלב", "לקנות חלב"),
    ]

    @Test(arguments: hebrewCases)
    func hebrewPhrasesLeaveTheTitle(text: String, title: String) {
        #expect(F.parse(text).title == title)
    }

    /// Titles that only look like requests keep every word — and their case.
    static let untouched: [String] = [
        "Add tests for the parser",
        "add salt to the soup",
        "call mom",
        "need milk",
        "pleased to meet Dan",
        "remember the milk",
        "ארוחת שבת עם המשפחה",
        "לקנות חלב",
    ]

    @Test(arguments: untouched)
    func otherTitlesAreLeftAlone(text: String) {
        #expect(F.parse(text).title == text)
    }

    /// Nothing would be left: the words stay the title.
    @Test(arguments: ["remind me", "please", "צריך", "todo:"])
    func aPhraseAloneStaysTheTitle(text: String) {
        #expect(F.parse(text).title == text)
    }

    @Test func datesAndTimesStillParse() {
        let draft = F.parse("remind me to call mom tomorrow 9am")
        #expect(draft.title == "Call mom")
        #expect(draft.due == DueDate(day: F.day(10, 6), minute: 9 * 60))

        let hebrew = F.parse("תזכיר לי להתקשר לאמא מחר ב-9")
        #expect(hebrew.title == "להתקשר לאמא")
        #expect(hebrew.due == DueDate(day: F.day(10, 6), minute: 9 * 60))
    }

    @Test func aTagStillPicksAndThePhraseStillGoes() {
        let draft = F.parse("remind me to book flights fri #thailand")
        #expect(draft.title == "Book flights")
        #expect(draft.category == .matched(F.thailand.id))
    }
}
