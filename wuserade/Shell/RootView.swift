// Minimum iOS 17.
//  The one root: it owns the tab selection, every navigation path and the Settings sheet, and picks the shell by
//  size class, never by device. iOS 18 and later: one sidebar-adaptable TabView. iOS 17: a TabView in compact
//  width and a three-column split in regular width. It also opens the poem a link or a tapped notification names.

import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(Library.self) private var library
    @Environment(PoemLinkInbox.self) private var poemLinks
    @SceneStorage("tab") private var tab: AppTab = .new
    @State private var paths = AppPaths()
    @State private var showSettings = false

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        Group {
            if #available(iOS 18, *) {
                TabView(selection: $tab) {
                    Tab(AppTab.new.title(compact: compact), systemImage: AppTab.new.symbol, value: AppTab.new) {
                        root(.new)
                    }
                    // Compact Home shows the themes as a section. `defaultVisibility(_:for:)` alone does not hide
                    // the tab without tab customization, so the tab is left out of the compact bar.
                    if !compact {
                        Tab(AppTab.themes.title(compact: compact), systemImage: AppTab.themes.symbol, value: AppTab.themes) {
                            root(.themes)
                        }
                    }
                    Tab(AppTab.poets.title(compact: compact), systemImage: AppTab.poets.symbol, value: AppTab.poets) {
                        root(.poets)
                    }
                    Tab(AppTab.liked.title(compact: compact), systemImage: AppTab.liked.symbol, value: AppTab.liked) {
                        root(.liked)
                    }
                    Tab(AppTab.search.title(compact: compact), systemImage: AppTab.search.symbol, value: AppTab.search,
                        role: .search) {
                        root(.search)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .tabViewSidebarHeader {
                    SettingsButton()
                }
                .modifier(MinimizesTabBar())
            } else if compact {
                TabView(selection: $tab) {
                    ForEach([AppTab.new, .poets, .liked, .search], id: \.self) { item in
                        root(item)
                            .tabItem { Label(item.title(compact: true), systemImage: item.symbol) }
                            .tag(item)
                    }
                }
            } else {
                SplitRoot(tab: $tab, paths: paths)
            }
        }
        .environment(\.openSettings, OpenSettingsAction { showSettings = true })
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .onChange(of: sizeClass, initial: true) { _, newClass in
            // Compact Home shows the themes as a section, so the hidden tab hands over to it.
            if newClass == .compact, tab == .themes { tab = .new }
        }
        // `initial` opens a link that arrived before this view existed, such as the tap that launched the app.
        .onChange(of: poemLinks.pending, initial: true) {
            guard let url = poemLinks.take() else { return }
            openPoemLink(url)
        }
    }

    /// Opens the poem on the first tab, over whatever that tab showed. A missing poem or a malformed link opens
    /// nothing.
    private func openPoemLink(_ url: URL) {
        guard let link = DeepLink.poem(from: url) else { return }
        Task {
            await PoemLinkOpener.open(id: link.id, fetch: library.fetchPoem) { poem in
                tab = .new
                paths.navigate(.reader(ReaderContext(single: PoemSummary(poem))), in: .new, split: !compact)
                if let source = link.source {
                    AnalyticsManager.shared.dailyOpen(source: source)
                }
            }
        }
    }

    private func root(_ tab: AppTab) -> some View {
        TabRoot(tab: tab, paths: paths) { compact in
            TabColumn(tab: tab, compact: compact)
        }
    }
}
