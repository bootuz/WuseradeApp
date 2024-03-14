//
//  FontSettingsViewModel.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 22.02.2024.
//

import Foundation

struct FontSettings: Codable {
    var fontName: String
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var characterSpacing: CGFloat
    var isBold: Bool
}

class FontSettingsManager: ObservableObject {
    @Published var currentSettings: FontSettings {
        didSet {
            saveSettings()
        }
    }

    init() {
        if let savedSettings = UserDefaults.standard.object(forKey: "fontSettings") as? Data,
            let decodedSettings = try? JSONDecoder().decode(FontSettings.self, from: savedSettings) {
            self.currentSettings = decodedSettings
        } else {
            self.currentSettings = FontSettings(fontName: "System", fontSize: 18, lineSpacing: 0, characterSpacing: 0, isBold: false)
        }
    }

    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(currentSettings) {
            UserDefaults.standard.set(encoded, forKey: "fontSettings")
        }
    }

    func setToDefaultSettings() {
        self.currentSettings = FontSettings(fontName: "System", fontSize: 18, lineSpacing: 0, characterSpacing: 0, isBold: false)
    }
}
