// Minimum iOS 17.
//  ЛъыхъуапӀэ. Nothing typed: recent searches (the one group on cell) and the themes. Typing: results update
//  as you type, scoped to poems or poets, with matched letters set one face heavier. Palochka variants fold
//  to one key, so 'цIык' finds 'ПСЫ ЦӀЫКӀУ'.

import FirebaseAnalytics
import SwiftUI

struct SearchView: View {
    @Environment(Library.self) private var library

    @AppStorage("search.recents") private var recentsStore = ""
    @State private var query = ""
    @State private var scope: SearchScope = .poems
    @State private var results: [PoemSummary]?
    @State private var failed = false

    private static let recentsLimit = 4
    private static let themeMatchLimit = 3

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var key: String { KabardianText.searchKey(trimmed) }
    private var recents: [String] { recentsStore.split(separator: "\n").map(String.init) }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                landing
            } else if scope == .poets {
                poetResults
            } else {
                poemResults
            }
        }
        .background(Palette.page)
        .navigationTitle("ЛъыхъуапӀэ")
        // Always visible: the default drawer hides the field under the title until the list is pulled down.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Усэм е усакӀуэм и цӀэр")
        .searchScopes($scope) {
            Text("Усэхэр").tag(SearchScope.poems)
            Text("УсакӀуэхэр").tag(SearchScope.poets)
        }
        .onSubmit(of: .search) { remember(trimmed) }
        .task(id: trimmed) { await search() }
        .task {
            await library.loadHome()
            await library.loadPoets()
        }
        .analyticsScreen(name: "SearchView")
    }

    // MARK: Nothing typed

    private var landing: some View {
        List {
            if !recents.isEmpty {
                Section {
                    ForEach(recents, id: \.self) { recent in
                        Button { query = recent } label: {
                            HStack(spacing: Space.three) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(Palette.inkTertiary)
                                    .accessibilityHidden(true)
                                Text(recent)
                                    .serif(.rowName)
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                        .contentRow()
                        .listRowBackground(Palette.cell)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(text: OwnerCopy.recents)
                        Spacer()
                        Button(OwnerCopy.clearRecents) { recentsStore = "" }
                            .font(.subheadline)
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            if let themes = library.themes {
                Section {
                    ForEach(themes) { themeRow($0) }
                } header: {
                    SectionLabel(text: "Зытеухуар")
                }
            }
        }
        .pageList()
    }

    // MARK: Results

    @ViewBuilder
    private var poemResults: some View {
        let themes = matchingThemes
        if failed {
            ScrollView {
                OfflineStateView { await search() }
            }
        } else if let results {
            if results.isEmpty && themes.isEmpty {
                ScrollView { EmptyStateView(title: OwnerCopy.noResults) }
            } else {
                PoemList(poems: results, highlight: trimmed) {
                    if !themes.isEmpty {
                        SectionLabel(text: "Зытеухуар")
                            .contentRow(separator: .hidden)
                        ForEach(themes) { themeRow($0) }
                        if !results.isEmpty {
                            SectionLabel(text: "Усэхэр")
                                .padding(.top, Space.four)
                                .contentRow(separator: .hidden)
                        }
                    }
                }
            }
        } else {
            LoadingPlaceholder(kind: .poemRows)
                .padding(.horizontal, Space.readingMargin)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var poetResults: some View {
        let poets = (library.poets ?? []).filter { KabardianText.searchKey($0.name).contains(key) }
        if poets.isEmpty {
            ScrollView { EmptyStateView(title: OwnerCopy.noResults) }
        } else {
            List(poets) { poet in
                NavigationLink(value: Route.poet(poet)) {
                    NameRowLabel(name: poet.name, highlight: trimmed)
                }
                .contentRow()
            }
            .pageList()
        }
    }

    private var matchingThemes: [Category] {
        guard let themes = library.themes else { return [] }
        return Array(themes.filter { KabardianText.searchKey($0.title).contains(key) }.prefix(Self.themeMatchLimit))
    }

    private func themeRow(_ theme: Category) -> some View {
        NavigationLink(value: Route.theme(theme)) {
            NameRowLabel(name: theme.title, highlight: trimmed)
        }
        .contentRow()
    }

    // MARK: Work

    private func search() async {
        guard !trimmed.isEmpty else {
            results = nil
            failed = false
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
            results = try await library.search(trimmed)
            failed = false
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func remember(_ query: String) {
        guard !query.isEmpty else { return }
        AnalyticsManager.shared.logEvent(name: "search", params: ["query": query])
        let kept = recents.filter { $0 != query }
        recentsStore = ([query] + kept).prefix(Self.recentsLimit).joined(separator: "\n")
    }
}
