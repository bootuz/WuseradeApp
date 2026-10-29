// Minimum iOS 17.
//  A list of poems. In compact width a row pushes the reader, which pages through the list.
//  In regular width the list selects into the detail and the system draws the selected row.

import SwiftUI

struct PoemList<Header: View>: View {
    let poems: [PoemSummary]
    var subtitle: PoemRowLabel.Subtitle = .author
    var highlight = ""
    var onRowAppear: ((PoemSummary) -> Void)?
    /// Liked: a trailing swipe removes the like at once, with no confirmation.
    var onUnlike: ((PoemSummary) -> Void)?
    /// Called with a row's id when the reader selects it (regular width). Programmatic changes to the
    /// selection, such as the detail's next-poem button, never call it.
    var onSelect: ((Int) -> Void)?
    @ViewBuilder var header: Header

    @Environment(SplitSelection.self) private var split: SplitSelection?

    var body: some View {
        if let split {
            @Bindable var split = split
            let selection = Binding<Int?>(
                get: { split.poemID },
                set: { id in
                    split.poemID = id
                    if let id { onSelect?(id) }
                }
            )
            List(selection: selection) {
                header
                rows(selecting: true)
            }
            .pageList()
            .onChange(of: split.poemID) { _, id in
                if let id, poems.contains(where: { $0.id == id }) { split.context = poems }
            }
        } else {
            List {
                header
                rows(selecting: false)
            }
            .pageList()
        }
    }

    @ViewBuilder
    private func rows(selecting: Bool) -> some View {
        ForEach(Array(poems.enumerated()), id: \.element.id) { index, poem in
            Group {
                if selecting {
                    PoemRowLabel(poem: poem, subtitle: subtitle, highlight: highlight)
                        .tag(poem.id)
                } else {
                    NavigationLink(value: Route.reader(ReaderContext(poems: poems, index: index))) {
                        PoemRowLabel(poem: poem, subtitle: subtitle, highlight: highlight)
                    }
                }
            }
            .contentRow(selectable: selecting)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let onUnlike {
                    Button(role: .destructive) { onUnlike(poem) } label: {
                        Label(OwnerCopy.unlikeSwipe, systemImage: "heart.slash")
                    }
                    .tint(Palette.likeSwipe)
                }
            }
            .onAppear { onRowAppear?(poem) }
        }
    }
}

extension PoemList where Header == EmptyView {
    init(poems: [PoemSummary], subtitle: PoemRowLabel.Subtitle = .author, highlight: String = "",
         onRowAppear: ((PoemSummary) -> Void)? = nil, onUnlike: ((PoemSummary) -> Void)? = nil) {
        self.init(poems: poems, subtitle: subtitle, highlight: highlight, onRowAppear: onRowAppear, onUnlike: onUnlike, onSelect: nil) {
            EmptyView()
        }
    }
}
