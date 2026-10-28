// Minimum iOS 17.
//  УсэщӀэхэр as a regular-width content column: the day's poem as one row under its label (no lozenge),
//  then the newest poems. Selecting a row opens it in the detail.

import SwiftUI

struct NewColumn: View {
    @Environment(Catalog.self) private var catalog

    var body: some View {
        Group {
            if let latest = catalog.latest {
                PoemList(poems: latest) {
                    if let poem = catalog.daysPoem {
                        SectionLabel(text: OwnerCopy.daysPageLabel)
                            .contentRow(separator: .hidden)
                        PoemRowLabel(poem: PoemSummary(poem))
                            .tag(poem.id)
                            .contentRow(selectable: true)
                    }
                }
                .refreshable { await catalog.refreshHome() }
            } else if catalog.homeFailed {
                ScrollView {
                    OfflineStateView { await catalog.refreshHome() }
                }
            } else {
                LoadingPlaceholder(kind: .poemRows)
                    .padding(.horizontal, Space.readingMargin)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.page)
        .navigationTitle("УсэщӀэхэр")
        .task { await catalog.loadHome() }
    }
}
