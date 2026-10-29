//
//  AnalyticsManager.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 24.02.2024.
//

import Foundation
import FirebaseAnalytics

class AnalyticsManager {
    static var shared = AnalyticsManager()

    private init() { }

    func logEvent(name: String, params: [String : Any]? = nil) {
        Analytics.logEvent(name, parameters: params)
    }

    /// A daily pick was opened. `source` is `home_poem`, `home_poet`, `home_short`, `widget` or `notification`.
    func dailyOpen(source: String) {
        logEvent(name: "daily_open", params: ["source": source])
    }

    /// The morning poem was turned on or off in Settings. `enabled` is the outcome: a refused permission logs 0.
    func morningPoem(enabled: Bool) {
        logEvent(name: "morning_poem", params: ["enabled": enabled ? 1 : 0])
    }

    /// The reader answered the morning-poem invitation on Home. `answer` is `accepted` or `dismissed`; accepting
    /// logs `accepted` even when iOS permission is then refused.
    func invitation(_ answer: String) {
        logEvent(name: "invitation", params: ["answer": answer])
    }

    /// A suggestion at the end of a poem was opened. `section` is `poet` or `similar`.
    func keepReadingOpen(section: String) {
        logEvent(name: "keep_reading_open", params: ["section": section])
    }
}
