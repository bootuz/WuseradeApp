// Minimum iOS 17.
//  One poem set like a page from a poetry book. Compact width hangs everything from one left axis at the
//  reading margin; regular width centres a block as wide as its longest line, capped at the measure.

import SwiftUI

struct ReaderPage: View {
    let summary: PoemSummary
    /// The folio: the poem's place in the list it was opened from.
    var position: (index: Int, total: Int)?
    var next: PoemSummary?
    var wide = false
    var onAuthor: (Author) -> Void
    var onNext: (PoemSummary) -> Void

    @Environment(ReaderPager.self) private var pager
    @Environment(Library.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.readTracker) private var readTracker
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var stanzaGap: CGFloat = 28

    /// The title's bottom edge, measured from the top of the scroll content.
    @State private var titleBottom: CGFloat = .greatestFiniteMagnitude
    /// How far the content's top has scrolled under the bar (iOS 18 and later).
    @State private var scrollDistance: CGFloat = 0
    /// iOS 17: the content's top and the bar's height, both in the scroll view's own space.
    @State private var contentTop: CGFloat = 0
    @State private var insetTop: CGFloat = 0
    @State private var width: CGFloat = 0
    /// The scroll view's height, and the closing lozenge's top in the scroll view's space: the end is on screen
    /// once the lozenge's top is above the bottom edge.
    @State private var scrollHeight: CGFloat = 0
    @State private var endTop: CGFloat = .greatestFiniteMagnitude

    private static let contentSpace = "readerContent"
    private static let scrollSpace = "readerScroll"

    /// Global coordinates count the bar twice inside the iOS 26 bar, so the running head works from the scroll
    /// view's own geometry instead.
    private var scrolled: CGFloat {
        if #available(iOS 18, *) { scrollDistance } else { insetTop - contentTop }
    }

    /// The loaded poem is the reader's current page while the app is in front.
    private var isShown: Bool {
        pager.currentID == summary.id && pager.poems[summary.id] != nil && scenePhase == .active
    }

    private var endVisible: Bool {
        endTop < scrollHeight
    }

    private var margin: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return Space.readingMarginAX }
        if wide && width >= Space.detailTarget { return Space.detailMargin }
        return Space.readingMargin
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, margin)
                .padding(.top, wide ? Space.twelve : Space.three)
                .padding(.bottom, Space.sixteen)
                .frame(maxWidth: .infinity, alignment: wide ? .center : .leading)
                .coordinateSpace(.named(Self.contentSpace))
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.scrollSpace)).minY } action: {
                    contentTop = $0
                }
        }
        .coordinateSpace(.named(Self.scrollSpace))
        .scrollIndicators(.hidden)
        .background(Palette.page)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { insetTop = $0 }
        .modifier(ScrollDistanceReader(distance: $scrollDistance))
        .onChange(of: scrolled > titleBottom, initial: true) { _, under in
            pager.titleUnderBar[summary.id] = under
        }
        .task(id: summary.id) { await pager.load(summary.id, from: library) }
        .onChange(of: isShown, initial: true) { reportShown() }
        .onChange(of: endVisible) { _, visible in
            if visible, isShown { readTracker?.reachedEnd(summary.id) }
        }
        // Coming back from a pushed screen changes no state, so `onChange` would not report it.
        .onAppear { reportShown() }
        .onDisappear { readTracker?.hidden(summary.id) }
    }

    /// Tells the reading history whether this poem is being read, and whether its end is already on screen.
    private func reportShown() {
        guard let readTracker else { return }
        if isShown {
            readTracker.shown(summary.id)
            if endVisible { readTracker.reachedEnd(summary.id) }
        } else {
            readTracker.hidden(summary.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let poem = pager.poems[summary.id], let parsed = pager.parsed[summary.id] {
            loaded(poem, parsed: parsed)
        } else if pager.failed.contains(summary.id) {
            OfflineStateView { await pager.retry(summary.id, from: library) }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                LoadingPlaceholder(kind: .reader)
                    .padding(.top, Space.eight)
            }
        }
    }

    private func loaded(_ poem: Poem, parsed: ParsedPoem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
            VerseView(poem: parsed, wide: wide)
                .padding(.top, Space.eight)
            Lozenge()
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.scrollSpace)).minY } action: {
                    endTop = $0
                }
                .padding(.top, stanzaGap)
            if let next {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.top, Space.twelve)
                NextPoemRow(poem: next) { onNext(next) }
            }
        }
        .transition(.opacity)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Space.two) {
            if let position, position.total > 1 {
                Text("\(position.index) / \(position.total)")
                    .serif(.folio)
                    .foregroundStyle(Palette.inkTertiary)
                    .accessibilityLabel(OwnerCopy.position(position.index, of: position.total))
            }
            PoemTitleBlock(poem: summary, large: wide) { onAuthor(summary.author) }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.contentSpace)).maxY } action: {
                    titleBottom = $0
                }
        }
    }
}
