// Minimum iOS 17.
//  The reader. Opened from a list it pages sideways through that list (cross-fading under Reduce Motion);
//  opened on its own it shows one poem. The bar carries the running head and Aa, Share and Like for the poem
//  on screen.

import SwiftUI

struct ReaderScreen: View {
    let context: ReaderContext
    /// The regular-width detail: poemBodyWide, dayTitle and the centred verse block.
    var wide = false
    /// Set in the regular-width detail, where the next poem is selected in the content column.
    var onNext: ((PoemSummary) -> Void)?

    @Environment(\.navigate) private var navigate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pager = ReaderPager()
    @State private var currentID: Int?
    @State private var showStyle = false

    init(context: ReaderContext, wide: Bool = false, onNext: ((PoemSummary) -> Void)? = nil) {
        self.context = context
        self.wide = wide
        self.onNext = onNext
        _currentID = State(initialValue: context.current?.id)
    }

    private var pages: Bool { context.fromList && context.poems.count > 1 }

    private var currentIndex: Int {
        context.poems.firstIndex { $0.id == currentID } ?? context.index
    }

    private var current: PoemSummary? {
        context.poems.indices.contains(currentIndex) ? context.poems[currentIndex] : nil
    }

    var body: some View {
        Group {
            if pages && !reduceMotion {
                pagingScroll
            } else if let current {
                page(current, at: currentIndex)
                    .id(current.id)
                    .transition(.opacity)
                    .simultaneousGesture(pages ? crossFadeSwipe : nil)
            }
        }
        .background(Palette.page)
        .navigationTitle(current.map(runningHead) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onChange(of: currentID, initial: true) { pager.currentID = currentID }
        .environment(pager)
    }

    // MARK: Pages

    private var pagingScroll: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(context.poems.enumerated()), id: \.element.id) { index, poem in
                    page(poem, at: index)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
    }

    private var crossFadeSwipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let width = value.translation.width
            guard abs(width) > 60, abs(width) > abs(value.translation.height) * 2 else { return }
            let target = currentIndex + (width < 0 ? 1 : -1)
            guard context.poems.indices.contains(target) else { return }
            withAnimation(.easeInOut(duration: 0.2)) { currentID = context.poems[target].id }
        }
    }

    private func page(_ poem: PoemSummary, at index: Int) -> some View {
        ReaderPage(
            summary: poem,
            position: context.fromList ? (index: index + 1, total: context.poems.count) : nil,
            next: context.next(after: index),
            wide: wide,
            onAuthor: { navigate(.poet($0)) },
            onNext: show
        )
    }

    private func show(_ next: PoemSummary) {
        if let onNext {
            onNext(next)
        } else if pages {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .default) { currentID = next.id }
        } else if let index = context.poems.firstIndex(of: next) {
            navigate(.reader(ReaderContext(poems: context.poems, index: index)))
        }
    }

    // MARK: Bar

    private func runningHead(_ poem: PoemSummary) -> String {
        poem.isUntitled ? poem.firstLine : poem.title
    }

    private var titleUnderBar: Bool {
        currentID.flatMap { pager.titleUnderBar[$0] } ?? false
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(current.map(runningHead) ?? "")
                .serif(.runningHead)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .opacity(titleUnderBar ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: titleUnderBar)
                .accessibilityHidden(true)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showStyle = true
            } label: {
                Label("Теплъэр", systemImage: "textformat.size")
            }
            .accessibilityAddTraits(showStyle ? .isSelected : [])
            .popover(isPresented: $showStyle) {
                ReadingStyleSheet()
            }

            if let id = currentID, let poem = pager.poems[id], let summary = current {
                ShareLink(item: PoemShare(poem: poem), preview: SharePreview(runningHead(summary))) {
                    Label("Дэгуэшэн", systemImage: "square.and.arrow.up")
                }
                LikeButton(poem: poem)
            }
        }
    }
}
