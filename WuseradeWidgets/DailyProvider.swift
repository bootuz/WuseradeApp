// Minimum iOS 17.
//  Reads today's `daily/{date}` over Firestore's REST API, keeps it in the App Group cache, and falls back to
//  that cache (from any earlier day) when the read fails. With today's document it reads again at the next local
//  midnight; after a failed read, or with an older day, within the hour. It serves
//  the configurable small widget as an App Intent provider and the other two as a plain one.

import Foundation
import WidgetKit

struct DailyProvider {
    var cache: DailyCache = .shared

    /// Never a made-up poem: the cached picks if there are any, or the empty state.
    func placeholder(in context: TimelineProviderContext) -> DailyEntry {
        DailyEntry(date: .now, picks: cache.load())
    }

    /// The gallery and the first frame: the cache alone, without waiting for the network.
    private func snapshot(smallPoem: DailyEntry.SmallPoem) -> DailyEntry {
        DailyEntry(date: .now, picks: cache.load(), smallPoem: smallPoem)
    }

    private func timeline(smallPoem: DailyEntry.SmallPoem) async -> Timeline<DailyEntry> {
        let now = Date.now
        let timeZone = TimeZone.current
        let fetched = await fetch(date: DailyDate.string(for: now, in: timeZone))
        let picks = DailyTimeline.picks(fetched: fetched, cached: cache.load())
        let entries = DailyTimeline.entries(for: picks, now: now, timeZone: timeZone).map {
            DailyEntry(date: $0.date, picks: $0.picks, smallPoem: smallPoem)
        }
        let reload = DailyTimeline.reloadDate(fetched: fetched != nil, picks: picks, now: now, timeZone: timeZone)
        return Timeline(entries: entries, policy: .after(reload))
    }

    /// Today's picks from the server, saved to the cache; nil when the read or the decoding fails.
    private func fetch(date: String) async -> DailyPicks? {
        let request = URLRequest(url: DailyTimeline.restURL(date: date), timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let picks = try? DailyTimeline.picks(fromREST: data)
        else { return nil }
        // This is the widget's own reload: asking the widgets to reload again would only repeat it.
        cache.save(picks, reloadingWidgets: false)
        return picks
    }
}

extension DailyProvider: AppIntentTimelineProvider {
    func snapshot(for configuration: SmallPoemIntent, in context: TimelineProviderContext) async -> DailyEntry {
        snapshot(smallPoem: configuration.kind.smallPoem)
    }

    func timeline(for configuration: SmallPoemIntent, in context: TimelineProviderContext) async -> Timeline<DailyEntry> {
        await timeline(smallPoem: configuration.kind.smallPoem)
    }
}

extension DailyProvider: TimelineProvider {
    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (DailyEntry) -> Void) {
        completion(snapshot(smallPoem: .shortPoem))
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        Task {
            completion(await timeline(smallPoem: .shortPoem))
        }
    }
}
