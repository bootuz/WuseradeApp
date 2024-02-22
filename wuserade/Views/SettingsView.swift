//
//  SettingsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var fontManager: FontSettingsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Тхыпхъэр") {
                    NavigationLink {
                        FontSettingsView(fontManager: fontManager)
                    } label: {
                        Text("Тхыпхъэр теухуэн")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FontSettingsView: View {
    @ObservedObject var fontManager: FontSettingsManager
    var body: some View {
        VStack {
            Form {
                Section(header: Text("")) {
                    Picker("Тхыпхъэр", selection: $fontManager.currentSettings.fontName) {
                        // Dynamically list fonts or add a fixed list
                        Text("System").tag("System")
                        Text("MarckScript").tag("MarckScript-Regular")
                            .font(.custom("MarckScript-Regular", size: 18))
                        Text("Georgia").tag("Georgia")
                        Text("Times New Roman").tag("Times New Roman")
                    }
                    HStack {
                        Slider(value: $fontManager.currentSettings.fontSize, in: 10...30, step: 1)
                        Text("\(Int(fontManager.currentSettings.fontSize)) pt")
                            .frame(width: 50)
                    }
                }
            }
        }
        .frame(height: 150)
        .toolbar(.hidden, for: .navigationBar)

        PoemView(viewModel: PoemViewModel(poem: Poem.example))
            .scrollDisabled(true)


    }
}

#Preview {
    SettingsView()
        .environmentObject(FontSettingsManager())
}
