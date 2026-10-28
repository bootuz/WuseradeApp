// Minimum iOS 17.
//  A poet's or a theme's poems: the DetailHeader as the first row, then the poems. The bar has only the back
//  button. An empty list gets its own words, never the offline state's.

import SwiftUI

struct PoemCollectionView: View {
    let name: String
    var subtitle: PoemRowLabel.Subtitle = .author
    var emptyTitle: String
    /// Nil until the catalog has loaded.
    let poems: [PoemSummary]?

    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if let poems, !poems.isEmpty {
                PoemList(poems: poems, subtitle: subtitle) {
                    DetailHeader(name: name, count: poems.count)
                        .contentRow(separator: .hidden)
                }
                .refreshable { await library.refreshHome() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DetailHeader(name: name)
                            .padding(.horizontal, Space.readingMargin)
                        if poems != nil {
                            EmptyStateView(title: emptyTitle)
                        } else if library.homeFailed {
                            OfflineStateView { await library.refreshHome() }
                        } else {
                            LoadingPlaceholder(kind: .poemRows)
                                .padding(.horizontal, Space.readingMargin)
                        }
                    }
                }
            }
        }
        .background(Palette.page)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The name is the first row; the bar keeps only the back button.
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
        }
        .task {
            if poems == nil { await library.loadHome() }
        }
    }
}
