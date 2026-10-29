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
                    // The app's page in the iOS Settings app has the per-app language. iOS restarts the app
                    // in the new language itself, which the app can't do.
                    Button {
                        if let settings = URL(string: UIApplication.openSettingsURLString) {
                            openURL(settings)
                        }
                    } label: {
                        // TODO(owner): copy. Meaning: "Language".
                        SettingsRowLabel(title: String(localized: "Бзэр"), systemImage: "globe", leavesApp: true)
                    }
                }

                Section {
                    Button {
                        openURL(AppLinks.review)
                    } label: {
                        SettingsRowLabel(title: String(localized: "Усэрадэр къэлъытэн"), systemImage: "star", leavesApp: true)
                    }
                    Button {
                        showContact = true
                    } label: {
                        SettingsRowLabel(title: String(localized: "Къэтхэн"), systemImage: "bubble.left")
                    }
                    .confirmationDialog("Къэтхэн", isPresented: $showContact, titleVisibility: .visible) {
                        Button("Telegram") { openURL(AppLinks.telegram) }
                        Button("Instagram") { openURL(AppLinks.instagram) }
                        Button("Email") { openURL(AppLinks.email) }
                    }
                    ShareLink(item: AppLinks.share) {
                        SettingsRowLabel(title: String(localized: "Дэгуэшэн"), systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Фидбэкыр")
                }

                Section {
                    if let privacy = AppLinks.privacy {
                        Button {
                            openURL(privacy)
                        } label: {
                            SettingsRowLabel(title: String(localized: "ФӀэкӀхэм щхьэкӀэ политикэ"), systemImage: "hand.raised", leavesApp: true)
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
