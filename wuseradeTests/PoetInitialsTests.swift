import Testing
@testable import Wuserade

struct PoetInitialsTests {
    @Test func `Two words give the section letter of each`() {
        #expect(PoetInitials.of("Хьа Бэ") == "ХьБ")
    }

    @Test func `One word gives its first letter`() {
        #expect(PoetInitials.of("Кхъа") == "Кхъ")
    }

    @Test func `A labialised letter counts as one letter like in the list`() {
        #expect(PoetInitials.of("Кхъу") == "Кхъу")
    }

    @Test func `Extra whitespace is ignored`() {
        #expect(PoetInitials.of("  Бэ   Мы  ") == "БМ")
    }

    @Test func `Only the first two words count`() {
        #expect(PoetInitials.of("Бэ Мы Щы") == "БМ")
    }

    @Test func `Lowercase names are capitalised`() {
        #expect(PoetInitials.of("хьа бэ") == "ХьБ")
    }

    @Test func `Palochka is written as U04C0`() {
        #expect(PoetInitials.of("К\u{04CF}а Бэ") == "К\u{04C0}Б")
        #expect(PoetInitials.of("К\u{04CF}уэ Бэ") == "К\u{04C0}уБ")
    }

    @Test func `Empty name gives no initials`() {
        #expect(PoetInitials.of("") == "")
    }
}
