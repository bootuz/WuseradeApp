//
//  PoemCategoriesViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation


@Observable
class CategoriesViewModel<Service: CategoriesServiceProtocol> {
    @ObservationIgnored
    private var service: Service

    var categories: [Category] = []
    var poems: [Poem] = []
    var isLoading: Bool = false

    init(service: Service) {
        self.service = service
    }

    @MainActor
    func fetchCategories() async {
        isLoading = true
        defer { isLoading = false }
        do {
            categories = try await service.fetch(.categories)
        } catch {
            print(error)
        }
    }

    @MainActor
    func fetchPoemsByCategory(id: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            poems = try await service.fetch(.poemsByCategory(id: id))
        } catch {
            print(error)
        }
    }
}
