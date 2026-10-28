// Minimum iOS 17.
//  УсэщӀэхэр as a regular-width content column: the day's poem as one row under its label (no lozenge),
//  then the newest poems. Selecting a row opens it in the detail.

import SwiftUI

struct NewColumn: View {
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if let latest = library.latest {
                PoemList(poems: latest) {
                    if let poem = library.daysPoem {
                        SectionLabel(text: OwnerCopy.daysPageLabel)
                            .contentRow(separator: .hidden)
                        PoemRowLabel(poem: PoemSummary(poem))
                            .tag(poem.id)
                            .contentRow(selectable: true)
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
}
