// Minimum iOS 17.
//  УсэщӀэхэр as a regular-width content column: the day's poem as one row under its label (no lozenge),
//  the short poem and the poet of the day as rows under their labels, then the newest poems. Selecting a row opens it in the detail.

import SwiftUI

struct NewColumn: View {
    @Environment(Library.self) private var library
    @Environment(\.navigate) private var navigate

    var body: some View {
        Group {
            if let latest = library.latest {
                PoemList(poems: latest, onSelect: logDailySelection) {
                    if let poem = library.daysPoem {
                        SectionLabel(text: OwnerCopy.daysPageLabel)
                            .contentRow(separator: .hidden)
                        PoemRowLabel(poem: PoemSummary(poem))
                            .tag(poem.id)
                            .contentRow(selectable: true)
                    }
                    if let daily = library.daily {
                        SectionLabel(text: OwnerCopy.shortPoem)
                            .padding(.top, Space.six)
                            .contentRow(separator: .hidden)
                        PoemRowLabel(poem: daily.shortPoem.summary)
                            .tag(daily.shortPoem.id)
                            .contentRow(selectable: true)

                        SectionLabel(text: OwnerCopy.poetOfTheDay)
                            .padding(.top, Space.six)
                            .contentRow(separator: .hidden)
                        Button {
                            AnalyticsManager.shared.dailyOpen(source: "home_poet")
                            navigate(.poet(daily.poet.author))
                        } label: {
                            HStack {
                                NameRowLabel(name: daily.poet.name)
                                Image(systemName: "chevron.forward")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.inkTertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contentRow()
                    }
                }
                .refreshable { await library.refreshHome() }
            } else if library.homeFailed {
                ScrollView {
                    OfflineStateView { await library.refreshHome() }
                }
            } else {
                LoadingPlaceholder(kind: .poemRows)
                    .padding(.horizontal, Space.readingMargin)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.page)
        .navigationTitle("УсэщӀэхэр")
        .task { await library.loadHome() }
    }

    /// A row the reader selected: the day's poem or the short poem is a daily open.
    private func logDailySelection(_ id: Int) {
        guard let daily = library.daily else { return }
        if id == daily.poem.id { AnalyticsManager.shared.dailyOpen(source: "home_poem") }
        else if id == daily.shortPoem.id { AnalyticsManager.shared.dailyOpen(source: "home_short") }
    }
}
