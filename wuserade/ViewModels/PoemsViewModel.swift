//
//  PoemsViewModel.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation
import Observation

@Observable
class PoemsViewModel {
    @ObservationIgnored
    private var service: PoemsService
    
    @ObservationIgnored
    private var page: Int = 1

    var isLoading: Bool = false
    var poems: [Poem] = [Poem]()
    var latestPoems: [Poem] = [Poem]()
    

    @ObservationIgnored
    private var totalPages: Int = 0

    init(service: PoemsService) {
        self.service = service
    }

    @MainActor
    func fetchPoems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.fetchPoems(page: page)
            poems = response.poems
            totalPages = response.totalPages
        } catch {
            print(error)
        }
    }

    @MainActor
    func refreshPoems() async {
        page = 1
        do {
            let response = try await service.fetchPoems(page: page)
            poems = response.poems
            totalPages = response.totalPages
        } catch {
            print(error)
        }
    }

    @MainActor
    func fetchMorePoemsIfNeeded(poem: Poem) async {
        guard isLast(poem) else { return }
        page += 1
        do {
            if page <= totalPages {
                let response = try await service.fetchPoems(page: page)
                poems += response.poems
            }
        } catch {
            print(error)
        }
    }

    @MainActor
    func fetchLatestPoems() async {
        do {
            latestPoems = try await service.fetchLatestPoems()
        } catch {
            print(error)
        }
    }

    private func isLast(_ poem: Poem) -> Bool {
        let thresholdIndex = poems.index(poems.endIndex, offsetBy: -10)
        return poems.firstIndex(where: { $0.id == poem.id }) == thresholdIndex
    }
}
