// Minimum iOS 17.
//  The day's poem by daily rotation: the date picks the poem on the device, the same for every reader, with no
//  server work and no daily effort from the owner. Today's pick is kept, so the day's page stays put all day
//  and opens offline. The poem changes at local midnight.

import Foundation

struct DailyRotation: DaysPoemSource {
    private let service = PoemsService(httpClient: URLSession.shared)
    private let defaults = UserDefaults.standard

    private enum Key {
        static let day = "daysPoem.day"
        static let poem = "daysPoem.poem"
    }

    func poem(for date: Date) async -> Poem? {
        let day = Self.dayNumber(of: date)
        if defaults.integer(forKey: Key.day) == day,
           let data = defaults.data(forKey: Key.poem),
           let kept = try? JSONDecoder().decode(Poem.self, from: data) {
            return kept
        }
        guard let pick = try? await pick(for: day) else { return nil }
        if let data = try? JSONEncoder().encode(pick) {
            defaults.set(day, forKey: Key.day)
            defaults.set(data, forKey: Key.poem)
        }
        return pick
    }

    /// The catalogue is paged newest first, 20 to a page. The day's hash picks a page and a place on it; a poem
    /// with fewer than two lines is passed over for the next one on the same page.
    private func pick(for day: Int) async throws -> Poem? {
        let first: PoemsResponse = try await service.fetch(.poems(page: 1))
        let hash = Self.mix(UInt64(bitPattern: Int64(day)))
        let page = Int(hash % UInt64(max(first.totalPages, 1))) + 1
        let poems: [Poem]
        if page == 1 {
            poems = first.poems
        } else {
            let response: PoemsResponse = try await service.fetch(.poems(page: page))
            poems = response.poems
        }
        guard !poems.isEmpty else { return nil }
        let start = Int((hash >> 32) % UInt64(poems.count))
        return poems.indices
            .map { poems[(start + $0) % poems.count] }
            .first { $0.content.split(whereSeparator: \.isNewline).count >= 2 }
    }

    /// Days since 1 January 2024 in the reader's own calendar day.
    static func dayNumber(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let epoch = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? .distantPast
        return calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// SplitMix64, so neighbouring days land far apart in the catalogue. Unlike `Hasher`, it gives every
    /// device the same value.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
