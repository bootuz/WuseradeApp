//
//  PoemTextView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 06.03.2024.
//

import SwiftUI

struct PoemTextView: View {
    @EnvironmentObject private var fontManager: FontSettingsManager
    var text: String
    var body: some View {
        Text(text)
            .font(fontManager.currentSettings.fontName == "System" ? .system(size: fontManager.currentSettings.fontSize) : .custom(fontManager.currentSettings.fontName, size: fontManager.currentSettings.fontSize))
            .lineSpacing(fontManager.currentSettings.lineSpacing)
            .kerning(fontManager.currentSettings.characterSpacing)
            .bold(fontManager.currentSettings.isBold)
    }
}

#Preview {
    PoemTextView(text: Poem.example.content)
        .environmentObject(FontSettingsManager())
}
