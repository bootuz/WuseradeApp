// Minimum iOS 17.
//  Усэхэр in compact width, read like a book's opening spread: the day's page (with the one-time morning-poem
//  invitation under it), the poet of the day and a short poem (each left out while there is no pick), the five newest
//  poems, and the themes, in one scroll.

import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(\.navigate) private var navigate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MorningPoemController.self) private var morning
    /// Observed so the invitation appears when the app records the third day and goes once it is answered. The
    /// values are read through `VisitDays`.
    @AppStorage(VisitDays.Keys.days) private var visitDaysStored = ""
    @AppStorage(VisitDays.Keys.invitationDone) private var invitationDoneStored = false

    private static let newestCount = 5

    var body: some View {
        Group {
            if let latest = library.latest, let themes = library.themes {
                content(newest: Array(latest.prefix(Self.newestCount)), themes: themes)
                    .transition(.opacity)
            } else if library.homeFailed {
                ScrollView {
                    OfflineStateView { await library.refreshHome() }
                }
            } else {
                ScrollView {
                    LoadingPlaceholder(kind: .poemRows)
                        .padding(.horizontal, Space.readingMargin)
                        .padding(.top, Space.six)
                }
                .scrollDisabled(true)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: library.latest == nil)
        .background(Palette.page)
        .navigationTitle("Усэхэр")
        .task { await library.loadHome() }
    }

    private func content(newest: [PoemSummary], themes: [Category]) -> some View {
        List {
            if let poem = library.daysPoem {
                DaysPageView(poem: poem) {
                    AnalyticsManager.shared.dailyOpen(source: "home_poem")
                    navigate(.reader(ReaderContext(single: PoemSummary(poem))))
                }
                .contentRow(separator: .hidden)

                if showsInvitation {
                    MorningInvitationCard()
                        .padding(.top, Space.six)
                        .contentRow(separator: .hidden)
                }
            }

            if let daily = library.daily {
                PoetOfTheDaySection(poet: daily.poet)
                ShortPoemSection(poem: daily.shortPoem)
            }

            SectionLabel(text: String(localized: "УсэщӀэхэр"))
                .padding(.top, Space.six)
                .contentRow(separator: .hidden)
            ForEach(Array(newest.enumerated()), id: \.element.id) { index, poem in
                NavigationLink(value: Route.reader(ReaderContext(poems: newest, index: index))) {
                    PoemRowLabel(poem: poem)
                }
                .contentRow()
            }

            SectionLabel(text: String(localized: "Зытеухуар"))
                .padding(.top, Space.six)
                .contentRow(separator: .hidden)
            ForEach(themes) { theme in
                NavigationLink(value: Route.theme(theme)) {
                    NameRowLabel(name: theme.title)
                }
                .contentRow()
            }

            if library.refreshFailed {
                RefreshFailedFootnote()
            }
        }
        .pageList()
        .refreshable { await library.refreshHome() }
    }

    private var showsInvitation: Bool {
        let days = VisitDays()
        #if DEBUG
        // `-previewInvitation` shows the invitation whatever the days, for screenshots, until it is answered.
        if ProcessInfo.processInfo.arguments.contains("-previewInvitation") {
            return MorningInvitation.shouldShow(visitDays: 3, done: days.invitationDone, enabled: morning.enabled)
        }
        #endif
        return MorningInvitation.shouldShow(visitDays: days.count, done: days.invitationDone, enabled: morning.enabled)
    }
}
