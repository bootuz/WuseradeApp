//
//  File.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import Foundation

@Observable
class AuthorsViewModel {
    
    @ObservationIgnored
    private var service: AuthorsService

    @ObservationIgnored
    private var page: Int = 1

    @ObservationIgnored
    private var totalPages: Int = 0
    
    var isLoading: Bool = false
    var authors: [Author] = [Author]()
    var poems: [Poem] = [Poem]()


    init(service: AuthorsService) {
        self.service = service
    }

    @MainActor
    func fetchAllAuthors() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.fetchAuthors(page: page)
            authors += response.authors
            totalPages = response.totalPages
        } catch {
            print(error)
        }
    }

    @MainActor
    func fetchNextAuthors() async {
        page += 1
        do {
            if page <= totalPages {
                let response = try await service.fetchAuthors(page: page)
                authors += response.authors
            }
        } catch {
            print(error)
        }
    }

    @MainActor
    func fetchPoemsOfAuthor(id: Int) async {
        isLoading = true
        defer { isLoading = false}
        do {
            poems = try await service.fetchPoemsOfAuthor(id: id, page: page)
        } catch {
            print(error)
        }
    }

    func hasReachedEnd(of author: Author) -> Bool {
        return authors.last?.id == author.id
    }
}
