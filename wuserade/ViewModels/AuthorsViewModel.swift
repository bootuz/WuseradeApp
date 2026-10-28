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

/// Groups authors into sections by the first letter of their name and sorts both the sections and the
/// authors inside them in Kabardian alphabet order (digraphs like "хь" and "къу" count as one letter).
@Observable
final class AuthorsViewModel {
    /// The last input and its grouping. Grouping runs on every body evaluation of the authors list and
    /// the alphabet comparison is not cheap, so an unchanged author list is not grouped again.
    @ObservationIgnored private var lastAuthors: [Author] = []
    @ObservationIgnored private var lastGroups: [(key: String, value: [Author])] = []

    func grouped(_ authors: [Author]) -> [(key: String, value: [Author])] {
        if authors == lastAuthors { return lastGroups }

        let grouped = Dictionary(grouping: authors) { $0.name.firstSymbol(from: Constants.alphabet) }
        let groups = grouped.map { (key: String, value: [Author]) -> (key: String, value: [Author]) in
            (key, value.sorted { compareNames($0.name, $1.name, usingAlphabet: Constants.alphabet) })
        }
        .sorted { compareNames($0.key, $1.key, usingAlphabet: Constants.alphabet) }

        lastAuthors = authors
        lastGroups = groups
        return groups
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
