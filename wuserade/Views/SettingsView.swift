//
//  SettingsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var requestReview
    @AppStorage("colorScheme") private var colorScheme: Bool = false

    @State private var showDialog: Bool = false

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

                Section("Фидбэкыр") {
                    Button(action: {
                        requestReview()
                    }, label: {
                        Label("Усэрадэр къэлъытэн", systemImage: "star")
                    })

                    Button(action: {
                        showDialog.toggle()
                    }, label: {
                        Label("Къэтхэн", systemImage: "bubble")
                    })
                    .confirmationDialog("", isPresented: $showDialog) {
                        Link("Telegram", destination: URL(string: "https://t.me/nart_kenobi")!)
                        Link("Instagram", destination: URL(string: "https://www.instagram.com/astemirboziy")!)
                        Link("Email", destination: URL(string: "mailto:astemirboziy@gmail.com")!)
                    }
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

                ToolbarItem(placement: .bottomBar) {
                    HStack(spacing: 3) {
                        Text("Made with ")
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                            .padding(.leading, -3)
                        Text("by Адыгэбзэ Хасэ.")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .analyticsScreen(name: "SettingsView")
        }
    }
}

#Preview {
    SettingsView()
        .tint(.primary)
}
