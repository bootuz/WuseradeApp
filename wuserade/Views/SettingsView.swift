//
//  SettingsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("colorScheme") private var colorScheme: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("Тхыпхъэр (шрифтыр)") {
                    NavigationLink {
                        FontSettingsView()
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
                    TitleView(title: "гъэпсыпlэ")
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
        .tint(.primary)
}
