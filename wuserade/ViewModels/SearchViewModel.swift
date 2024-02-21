//
//  SeachViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 18.02.2024.
//

import Foundation


@Observable
class SearchViewModel {
    @ObservationIgnored
    private var service: PoemsService

    var poems: [Poem] = [Poem]()
    var query: String = ""

    init(service: PoemsService) {
        self.service = service
    }

    
    @MainActor
    func searchPoems(query: String) async {
        do {
            poems = try await service.searchPoems(query: query)
        } catch {
            print(error)
        }
    }
}
