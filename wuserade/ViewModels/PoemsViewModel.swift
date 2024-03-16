//
//  PoemsViewModel.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation
import Observation

@Observable
class PoemsViewModel<Service: PoemsServiceProtocol> {
    @ObservationIgnored
    private var service: Service

    @ObservationIgnored
    private var page: Int = 1

    var isLoading: Bool = false
    var poems: [Poem] = [Poem]()
    var latestPoems: [Poem] = [Poem]()
    

    @ObservationIgnored
    private var totalPages: Int = 0

    init(service: Service) {
        self.service = service
    }

    @MainActor
    func allPoems() async {
        isLoading = true
        defer { isLoading = false }
        await fetchPoems()
    }

    @MainActor
    func refreshPoems() async {
        page = 1
        await fetchPoems()
    }

    @MainActor
    func fetchPoem(by id: Int) async -> Poem? {
        do {
            return try await service.fetch(.fetchPoem(id: id))
        } catch {
            print(error)
            return nil
        }
    }

    @MainActor
    func fetchMorePoemsIfNeeded(poem: Poem) async {
        guard isLast(poem) else { return }
        page += 1
        do {
            if page <= totalPages {
                let response: PoemsResponse = try await service.fetch(.poems(page: page))
                poems += response.poems
            }
        } catch {
            print(error)
        }
    }

    @MainActor
    func fetchLatestPoems() async {
        do {
            latestPoems = try await service.fetch(.fetchLatestPoems)
        } catch {
            print(error)
        }
    }

    private func isLast(_ poem: Poem) -> Bool {
        let thresholdIndex = poems.index(poems.endIndex, offsetBy: -10)
        return poems.firstIndex(where: { $0.id == poem.id }) == thresholdIndex
    }

    private func fetchPoems() async {
        do {
            let response: PoemsResponse = try await service.fetch(.poems(page: page))
            poems = response.poems
            totalPages = response.totalPages
        } catch {
            print(error)
        }
    }
}
