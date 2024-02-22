//
//  PoemViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import Foundation


@Observable
class PoemViewModel {
    var poem: Poem

    init(poem: Poem) {
        self.poem = poem
    }
}
