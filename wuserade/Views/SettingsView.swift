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
    @AppStorage("colorScheme") private var colorScheme: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("Тхыпхъэр (шрифтыр)") {
                    NavigationLink {
                        FontSettingsView(fontManager: fontManager)
                    } label: {
                        Label("Тхыпхъэр теухуэн", systemImage: "textformat")
                    }
                }

                Section("Плъыфэр") {
                    Toggle(isOn: $colorScheme, label: {
                        Label("Плъыфэр", systemImage: "circle.lefthalf.filled")
                    })
                    .tint(.green)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("гъэпсыпlэ")
                        .font(.custom("MarckScript-Regular", size: 25))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(FontSettingsManager())
        .tint(.primary)
}
