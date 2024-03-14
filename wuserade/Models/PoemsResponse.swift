//
//  PoemsResponse.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 14.03.2024.
//

import Foundation

struct PoemsResponse: Codable {
    let poems: [Poem]
    let totalPages: Int
    let currentPage: String
}
