// Minimum iOS 17.
//  A poet's or a theme's poems: a header as the first row, then the poems. The header is a DetailHeader unless
//  the caller brings its own, and gets the poem count, or nil while there is none to show. The bar has only the
//  back button. An empty list gets its own words, never the offline state's.

import SwiftUI

struct PoemCollectionView<Header: View>: View {
    let name: String
    var subtitle: PoemRowLabel.Subtitle = .author
    var emptyTitle: String
    /// Nil until the catalog has loaded.
    let poems: [PoemSummary]?
    /// True when the header centres its content, so its row is inset equally on both sides.
    var headerIsCentred = false
    @ViewBuilder let header: (_ count: Int?) -> Header

    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if let poems, !poems.isEmpty {
                PoemList(poems: poems, subtitle: subtitle) {
                    header(poems.count)
                        .contentRow(separator: .hidden, centred: headerIsCentred)
                }
                .refreshable { await library.refreshHome() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(nil)
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

extension PoemCollectionView where Header == DetailHeader {
    init(name: String, subtitle: PoemRowLabel.Subtitle = .author, emptyTitle: String, poems: [PoemSummary]?) {
        self.init(name: name, subtitle: subtitle, emptyTitle: emptyTitle, poems: poems) {
            DetailHeader(name: name, count: $0)
        }
    }
}
