// Minimum iOS 17.
//  ГъэпсыпӀэ: one sheet (a form sheet on iPad) on page-elevated. Subviews push inside it.
//  Аккаунт comes first. The Плъыфэр toggle is gone, since the palette follows the system appearance.

import FirebaseAnalytics
import SwiftUI

struct SettingsSheet: View {
    @Environment(\.openURL) private var openURL
    @State private var showContact = false

    var body: some View {
        NavigationStack {
            Form {
                AccountSection()

                Section {
                    NavigationLink {
                        ReadingStyleForm()
                            .navigationTitle("Теплъэр")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        SettingsRowLabel(title: "Теплъэр теухуэн", systemImage: "textformat")
                    }
                } header: {
                    Text("Текстыр")
                }

                Section {
                    Button {
                        openURL(AppLinks.review)
                    } label: {
                        SettingsRowLabel(title: "Усэрадэр къэлъытэн", systemImage: "star", leavesApp: true)
                    }
                    Button {
                        showContact = true
                    } label: {
                        SettingsRowLabel(title: "Къэтхэн", systemImage: "bubble.left")
                    }
                    .confirmationDialog("Къэтхэн", isPresented: $showContact, titleVisibility: .visible) {
                        Button("Telegram") { openURL(AppLinks.telegram) }
                        Button("Instagram") { openURL(AppLinks.instagram) }
                        Button("Email") { openURL(AppLinks.email) }
                    }
                    ShareLink(item: AppLinks.share) {
                        SettingsRowLabel(title: "Дэгуэшэн", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Фидбэкыр")
                }

                Section {
                    if let privacy = AppLinks.privacy {
                        Button {
                            openURL(privacy)
                        } label: {
                            SettingsRowLabel(title: "ФӀэкӀхэм щхьэкӀэ политикэ", systemImage: "hand.raised", leavesApp: true)
                        }
                    }
                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        Text(OwnerCopy.acknowledgements).foregroundStyle(Palette.ink)
                    }
                }

                Section {
                    SettingsColophon()
                }
                .listRowBackground(Color.clear)
            }
            .listRowBackground(Palette.cellElevated)
            .scrollContentBackground(.hidden)
            .background(Palette.pageElevated)
            .textCase(nil)
            .navigationTitle("ГъэпсыпӀэ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseButton()
                }
            }
        }
        .presentationBackground(Palette.pageElevated)
        .modifier(FormSheetSizing())
        .analyticsScreen(name: "SettingsView")
    }
}
