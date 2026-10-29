from wuserade_daily import text

PALOCHKA = "Ӏ"
# What the app's Author.swift calls the placeholder author of poems with no known poet.
UNKNOWN = "Зытхар тщӀэкъым"


def test_normalize_turns_latin_lookalikes_between_cyrillic_letters_into_palochka():
    assert text.normalize("тщIэкъым") == "тщӀэкъым"
    assert text.normalize("тщlэкъым") == "тщӀэкъым"
    assert text.normalize("тщ1экъым") == "тщӀэкъым"


def test_normalize_turns_small_palochka_and_ukrainian_i_into_palochka():
    assert text.normalize("тщ\u04cfэ") == "тщӀэ"
    assert text.normalize("тщ\u0406э") == "тщӀэ"


def test_normalize_keeps_the_real_palochka():
    assert text.normalize("тщӀэ") == "тщӀэ"


def test_normalize_folds_a_palochka_at_the_start_or_end_of_a_word():
    assert text.normalize("Iэ") == "Ӏэ"
    assert text.normalize("лI") == "лӀ"


def test_normalize_leaves_latin_text_and_numbers_alone():
    assert text.normalize("Hello, Illinois 1990") == "Hello, Illinois 1990"
    assert text.normalize("I") == "I"
    assert text.normalize("в 1990 году") == "в 1990 году"


def test_normalize_trims():
    assert text.normalize("  тщIэ \n") == "тщӀэ"


def test_sentence_case_keeps_palochka():
    assert text.sentence_case("АНЭМ И ПСАЛЪЭ") == "Анэм и псалъэ"
    assert text.sentence_case("ПСЫ ЦӀЫКӀУ") == "Псы цӀыкӀу"
    assert text.sentence_case("ПСЫ ЦӀЫКӀУ").count(PALOCHKA) == 2


def test_sentence_case_restores_palochka_written_as_latin_letters():
    assert text.sentence_case("ПСЫ ЦIЫКIУ") == "Псы цӀыкӀу"


def test_sentence_case_of_a_title_starting_with_a_palochka_and_of_an_empty_title():
    assert text.sentence_case("Iэ") == "Ӏэ"
    assert text.sentence_case("\u04cfэ") == "Ӏэ"
    assert text.sentence_case("") == ""


def test_unknown_author_matches_any_palochka_spelling():
    assert text.is_unknown_author("Зытхар тщIэкъым")
    assert text.is_unknown_author(UNKNOWN)
    assert text.is_unknown_author("Зытхар тщ\u04cfэкъым")
    assert text.is_unknown_author("Зытхар тщlэкъым")


def test_unknown_author_ignores_case_and_surrounding_space():
    assert text.is_unknown_author("  ЗЫТХАР ТЩIЭКЪЫМ ")
    assert text.is_unknown_author("зытхар тщӀэкъым")


def test_a_real_poet_is_not_the_unknown_author():
    assert not text.is_unknown_author("Бейтыгъуэн Алим")
    assert not text.is_unknown_author("")


def test_first_lines_takes_the_first_non_blank_lines_stripped():
    poem = "\n  one  \n\n   \ntwo\nthree\nfour\n"
    assert text.first_lines(poem, 2) == ["one", "two"]
    assert text.first_lines(poem, 3) == ["one", "two", "three"]


def test_first_lines_returns_what_there_is_when_the_text_is_short():
    assert text.first_lines("only\n\n", 4) == ["only"]
    assert text.first_lines("", 4) == []
    assert text.first_lines("   \n \n", 4) == []


def test_first_lines_splits_on_crlf_and_cr_like_the_admin_line_count():
    assert text.first_lines("a\r\nb\rc\nd", 4) == ["a", "b", "c", "d"]


def test_first_lines_with_zero_or_negative_n_is_empty():
    assert text.first_lines("a\nb", 0) == []
    assert text.first_lines("a\nb", -1) == []
