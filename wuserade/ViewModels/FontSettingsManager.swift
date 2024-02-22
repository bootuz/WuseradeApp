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
}

class FontSettingsManager: ObservableObject {
    @Published var currentSettings: FontSettings {
        didSet {
            saveSettings()
            print(currentSettings)
        }
    }

    init() {
        if let savedSettings = UserDefaults.standard.object(forKey: "fontSettings") as? Data,
            let decodedSettings = try? JSONDecoder().decode(FontSettings.self, from: savedSettings) {
            self.currentSettings = decodedSettings
        } else {
            self.currentSettings = FontSettings(fontName: "System", fontSize: 18)
        }
    }

    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(currentSettings) {
            UserDefaults.standard.set(encoded, forKey: "fontSettings")
        }
    }
}
