//
//  Author.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation

struct Author: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct AllAuthors: Codable {
    let authors: [Author]
    let totalPages: Int
    let currentPage: String
}
