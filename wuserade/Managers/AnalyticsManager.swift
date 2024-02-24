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
}
