//
//  SettingsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI
import StoreKit
import Pow
import SFSafeSymbols

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var requestReview
    @AppStorage("colorScheme") private var colorScheme: Bool = false

    @State private var showDialog: Bool = false
    @State private var isAnimated = false

    var body: some View {
        NavigationStack {
            List {
                Section("Текстыр") {
                    NavigationLink {
                        FontSettingsView()
                    } label: {
                        Label("Теплъэр теухуэн", systemSymbol: SFSymbol.textformat)
                    }
                }

                Section("Плъыфэр") {
                    Toggle(isOn: $colorScheme, label: {
                        Label(colorScheme ? "Хужьу" : "Фlыцly", systemSymbol: SFSymbol.circleLefthalfFilled)
                    })
                    .tint(.green)
                }

                Section("Фидбэкыр") {
                    Button(action: {
                        RateManager.shared.rateApp()
                    }, label: {
                        Label("Усэрадэр къэлъытэн", systemSymbol: SFSymbol.star)
                    })

                    Button(action: {
                        showDialog.toggle()
                    }, label: {
                        Label("Къэтхэн", systemSymbol: SFSymbol.bubble)
                    })
                    .confirmationDialog("", isPresented: $showDialog) {
                        Link("Telegram", destination: URL(string: "https://t.me/nart_kenobi")!)
                        Link("Instagram", destination: URL(string: "https://www.instagram.com/astemirboziy")!)
                        Link("Email", destination: URL(string: "mailto:astemirboziy@gmail.com")!)
                    }

                    ShareLink(item: URL(string: "https://apple.co/3OWuu5b")!) {
                        Label("Дэгуэшэн", systemSymbol: SFSymbol.squareAndArrowUp)
                    }
                }
            }
            .onAppear {
                withAnimation {
                    isAnimated = true
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
                        Image(systemSymbol: SFSymbol.heartFill)
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
        .environmentObject(FontSettingsManager())
}
