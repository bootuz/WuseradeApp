// Minimum iOS 17.
//  The day's poem by daily rotation: the date picks the poem on the device, the same for every reader, with no
//  server work and no daily effort from the owner. Today's pick is kept, so the day's page stays put all day
//  and opens offline. The poem changes at local midnight.

import Foundation

struct DailyRotation: DaysPoemSource {
    let repository: ContentRepository
    private let defaults = UserDefaults.standard

    /// How many neighbours to try when the pick is too short for a page.
    private static let attempts = 5

    private enum Key {
        static let day = "daysPoem.day"
        static let poem = "daysPoem.poem"
    }

    init(repository: ContentRepository) {
        self.repository = repository
    }

    func poem(for date: Date, in entries: [PoemSummary]) async -> Poem? {
        let day = Self.dayNumber(of: date)
        if defaults.integer(forKey: Key.day) == day,
           let data = defaults.data(forKey: Key.poem),
           let kept = try? JSONDecoder().decode(Poem.self, from: data) {
            return kept
        }
        guard let pick = await pick(for: day, in: entries) else { return nil }
        if let data = try? JSONEncoder().encode(pick) {
            defaults.set(day, forKey: Key.day)
            defaults.set(data, forKey: Key.poem)
        }
        return pick
    }

    /// The day's hash picks a place in the catalog, in id order so every device agrees. A poem with fewer than
    /// two lines is passed over for the next one.
    private func pick(for day: Int, in entries: [PoemSummary]) async -> Poem? {
        let ids = entries.map(\.id).sorted()
        guard !ids.isEmpty else { return nil }
        let start = Int(Self.mix(UInt64(bitPattern: Int64(day))) % UInt64(ids.count))
        for offset in 0..<min(Self.attempts, ids.count) {
            guard let poem = try? await repository.fetchPoem(id: ids[(start + offset) % ids.count]) else { return nil }
            if poem.content.split(whereSeparator: \.isNewline).count >= 2 { return poem }
        }
        return nil
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
