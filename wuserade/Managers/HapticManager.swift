//
//  HapticManager.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import UIKit


final class HapticManager {

    static let shared = HapticManager()

    private init() {}

    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
