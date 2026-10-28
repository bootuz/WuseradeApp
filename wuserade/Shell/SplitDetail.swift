// Minimum iOS 17.
//  The regular-width detail: the selected poem in the wide reader, or, with nothing selected, the day's page
//  (УсэщӀэхэр only) or a quiet empty state.

import SwiftUI

struct SplitDetail: View {
    let selection: SplitSelection
    var showsDaysPage = false

    @Environment(Catalog.self) private var catalog

    var body: some View {
        NavigationStack {
            Group {
                if let context = readerContext, let id = context.current?.id {
                    ReaderScreen(context: context, wide: true) { next in
                        selection.poemID = next.id
                    }
                    .id(id)
                } else if showsDaysPage, let poem = catalog.daysPoem {
                    ScrollView {
                        DaysPageView(poem: poem) {
                            selection.poemID = poem.id
                        }
                        .frame(maxWidth: Space.detailTarget)
                        .padding(.horizontal, Space.detailMargin)
                        .padding(.top, Space.twelve)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        EmptyStateView(title: OwnerCopy.nothingSelected)
                    }
                }
            }
            .background(Palette.page)
        }
    }

    private var readerContext: ReaderContext? {
        if let context = selection.readerContext { return context }
        if let id = selection.poemID, let poem = catalog.poem(id) {
            return ReaderContext(single: PoemSummary(poem))
        }
        return nil
    }
}
