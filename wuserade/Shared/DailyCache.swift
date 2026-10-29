// Minimum iOS 17.
//  The last daily document the app or the widget loaded, kept as `daily.json` in the App Group, so Home and the
//  widget show today's picks offline. Without a directory (no App Group container, as in an unprovisioned
//  simulator or the tests) it loads and saves nothing.

import Foundation
import WidgetKit

struct DailyCache {
    static let appGroup = "group.com.nart.wuserade"

    static let shared = DailyCache(
        directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    )

    private let fileURL: URL?

    init(directory: URL?) {
        fileURL = directory?.appendingPathComponent("daily.json", isDirectory: false)
    }

    func load() -> DailyPicks? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DailyPicks.self, from: data)
    }

    /// Keeps `picks`, and asks the widgets to reload when the stored day changes. The widget passes
    /// `reloadingWidgets: false`: it saves while building its own timeline, which a reload would only repeat.
    func save(_ picks: DailyPicks, reloadingWidgets: Bool = true) {
        guard let fileURL, let data = try? JSONEncoder().encode(picks) else { return }
        let previousDate = load()?.date
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
        if reloadingWidgets, previousDate != picks.date {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
