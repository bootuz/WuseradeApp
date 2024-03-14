//
//  Constants.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

struct Constants {

    struct ErrorMessages {
        static let somethingWentWrong = "Something went wrong."
        static let invalidResponse = "Invalid response."
        static let invalidCode = "Invalid code."
        static let decodeError = "Could not load data"
    }

    static let alphabet: [String] = [
        "а", "э", "б", "в", "г", "гу", "гъ",
        "гъу", "д", "дж", "дз", "е", "ё", "ж", "жь",
        "з", "и", "й", "к", "ку", "кӏ", "кӏу",
        "къ", "къу", "кхъ", "кхъу", "л", "лъ",
        "лӏ", "м", "н", "о", "п", "пӏ", "р",
        "с", "т", "тӏ", "у", "ф", "фӏ", "х",
        "ху", "хь", "хъ", "хъу", "ц", "цӏ",
        "ч", "ш", "щ", "щӏ", "ы", "ъ", "ь",
        "ю", "я", "ӏ", "ӏу"
    ]
}
