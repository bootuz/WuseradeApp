//
//  PoemViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import Foundation


@Observable
class PoemViewModel<Service: PoemsServiceProtocol> {
    var poem: Poem?

    private var service: Service

    init(service: Service) {
        self.service = service
    }

    @MainActor
    func fetchPoem(by id: Int) async {
        do {
            poem = try await service.fetch(PoemsEndpoint.fetchPoem(id: id))
        } catch {
            print(error)
        }
    }
}
