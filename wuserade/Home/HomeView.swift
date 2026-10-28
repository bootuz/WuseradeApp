// Minimum iOS 17.
//  Усэхэр in compact width, read like a book's opening spread: the day's page (left out while there is no
//  pick), the five newest poems, and the themes, in one scroll.

import SwiftUI

struct HomeView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(\.navigate) private var navigate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let newestCount = 5

    var body: some View {
        Group {
            if let latest = catalog.latest, let themes = catalog.themes {
                content(newest: Array(latest.prefix(Self.newestCount)), themes: themes)
                    .transition(.opacity)
            } else if catalog.homeFailed {
                ScrollView {
                    OfflineStateView { await catalog.refreshHome() }
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: catalog.latest == nil)
        .background(Palette.page)
        .navigationTitle("Усэхэр")
        .task { await catalog.loadHome() }
    }

    private func content(newest: [PoemSummary], themes: [Category]) -> some View {
        List {
            if let poem = catalog.daysPoem {
                DaysPageView(poem: poem) {
                    navigate(.reader(ReaderContext(single: PoemSummary(poem))))
                }
                .contentRow(separator: .hidden)
            }

            SectionLabel(text: "УсэщӀэхэр")
                .padding(.top, Space.six)
                .contentRow(separator: .hidden)
            ForEach(Array(newest.enumerated()), id: \.element.id) { index, poem in
                NavigationLink(value: Route.reader(ReaderContext(poems: newest, index: index))) {
                    PoemRowLabel(poem: poem)
                }
                .contentRow()
            }

            SectionLabel(text: "Зытеухуар")
                .padding(.top, Space.six)
                .contentRow(separator: .hidden)
            ForEach(themes) { theme in
                NavigationLink(value: Route.theme(theme)) {
                    NameRowLabel(name: theme.title)
                }
                .contentRow()
            }

            if catalog.refreshFailed {
                RefreshFailedFootnote()
            }
        }
        .pageList()
        .refreshable { await catalog.refreshHome() }
    }
}
