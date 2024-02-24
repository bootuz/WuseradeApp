//
//  PoemCategoriesViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation


@Observable
class PoemCategoriesViewModel {
    @ObservationIgnored
    private var service: PoemCategoriesService
    
    var categories: [PoemCategory] = []
    var poems: [Poem] = []
    var isLoading: Bool = false

    init(service: PoemCategoriesService) {
        self.service = service
    }

    @MainActor
    func fetchCategories() async {
        isLoading = true
        defer { isLoading = false }
        do {
            categories = try await service.fetchCategories()
        } catch {
            print(error)
        }
    }

    @MainActor
    func fetchPoemsByCategory(id: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            poems = try await service.fetchPoemsByCategory(id: id)
        } catch {
            print(error)
        }
    }
}
