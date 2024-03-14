//
//  File.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import Foundation

extension String {
    func firstSymbol(from alphabet: [String]) -> String {
        let sortedAlphabet = alphabet.sorted { $0.count > $1.count }

        for symbol in sortedAlphabet {
            if self.lowercased().starts(with: symbol) {
                return symbol
            }
        }

        return self.prefix(1).lowercased()
    }

    func breakdown(usingAlphabet alphabet: [String]) -> [String] {
        var result: [String] = []
        var currentIndex = self.startIndex

        while currentIndex < self.endIndex {
            var matched = false

            for symbol in alphabet.sorted(by: { $0.count > $1.count }) {
                if self[currentIndex...].lowercased().starts(with: symbol) {
                    result.append(symbol)
                    currentIndex = self.index(currentIndex, offsetBy: symbol.count)
                    matched = true
                    break
                }
            }

            if !matched {
                currentIndex = self.index(after: currentIndex)
            }
        }

        return result
    }
}

@Observable
class AuthorsViewModel<Service: AuthorsServiceProtocol> {
    @ObservationIgnored
    private var service: Service

    @ObservationIgnored
    private var page: Int = 1

    @ObservationIgnored
    private var totalPages: Int = 0
    
    var isLoading: Bool = false
    var authors: [Author] = [Author]()
    var poems: [Poem]


    init(service: Service, poems: [Poem] = []) {
        self.poems = poems
        self.service = service
    }

    var groupedAndSortedAuthors: [(key: String, value: [Author])] {
        let grouped = Dictionary(grouping: authors) { $0.name.firstSymbol(from: Constants.alphabet) }

        return grouped.map { (key: String, value: [Author]) -> (String, [Author]) in
            (key, value.sorted { compareNames($0.name, $1.name, usingAlphabet: Constants.alphabet) })
        }
        .sorted { compareNames($0.key, $1.key, usingAlphabet: Constants.alphabet) }
    }

    @MainActor
    func fetchAllAuthors() async {
        isLoading = true
        defer { isLoading = false }
        do {
            authors = try await service.fetch(.authorsV2)
        } catch {
            print(error)
        }
    }

    @MainActor
    func refreshAuthors() async {
        do {
            authors = try await service.fetch(.authorsV2)
        } catch {
            print(error)
        }
    }


    @MainActor
    func fetchPoemsOfAuthor(id: Int) async {
        isLoading = true
        defer { isLoading = false}
        do {
            poems = try await service.fetch(.poemsOfAuthor(id: id))
        } catch {
            print(error)
        }
    }

    private func compareNames(_ name1: String, _ name2: String, usingAlphabet alphabet: [String]) -> Bool {
        let name1Parts = name1.breakdown(usingAlphabet: alphabet)
        let name2Parts = name2.breakdown(usingAlphabet: alphabet)

        for (part1, part2) in zip(name1Parts, name2Parts) {
            if part1 != part2 {
                return alphabet.firstIndex(of: part1)! < alphabet.firstIndex(of: part2)!
            }
        }

        return name1Parts.count < name2Parts.count
    }
}
