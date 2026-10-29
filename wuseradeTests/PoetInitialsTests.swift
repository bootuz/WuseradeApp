import XCTest
@testable import Wuserade

final class PoetInitialsTests: XCTestCase {
    func testTwoWordsGiveTheSectionLetterOfEach() {
        XCTAssertEqual(PoetInitials.of("Хьа Бэ"), "ХьБ")
    }

    func testOneWordGivesItsFirstLetter() {
        XCTAssertEqual(PoetInitials.of("Кхъа"), "Кхъ")
    }

    func testALabialisedLetterCountsAsOneLetterLikeInTheList() {
        XCTAssertEqual(PoetInitials.of("Кхъу"), "Кхъу")
    }

    func testExtraWhitespaceIsIgnored() {
        XCTAssertEqual(PoetInitials.of("  Бэ   Мы  "), "БМ")
    }

    func testOnlyTheFirstTwoWordsCount() {
        XCTAssertEqual(PoetInitials.of("Бэ Мы Щы"), "БМ")
    }

    func testLowercaseNamesAreCapitalised() {
        XCTAssertEqual(PoetInitials.of("хьа бэ"), "ХьБ")
    }

    func testPalochkaIsWrittenAsU04C0() {
        XCTAssertEqual(PoetInitials.of("К\u{04CF}а Бэ"), "К\u{04C0}Б")
        XCTAssertEqual(PoetInitials.of("К\u{04CF}уэ Бэ"), "К\u{04C0}уБ")
    }

    func testEmptyNameGivesNoInitials() {
        XCTAssertEqual(PoetInitials.of(""), "")
    }
}
