// Minimum iOS 17.
//  УсакӀуэхэр: one pinned section per Kabardian letter in the alphabet's order (digraphs such as КӀ and Хь
//  are letters of their own), and 'author unknown' in italic in its own last section.

import FirebaseAnalytics
import SwiftUI

struct PoetsView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var sections: [LetterSection] = []
    @State private var unknown: [Author] = []

    private static let unknownName = KabardianText.searchKey("Зытхар тщӀэкъым")

    var body: some View {
        Group {
            if catalog.poets != nil {
                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.poets) { row($0) }
                        } header: {
                            header(section.letter)
                        }
                    }
                    if !unknown.isEmpty {
                        Section {
                            ForEach(unknown) { row($0, italic: true) }
                        } header: {
                            header(OwnerCopy.unknownAuthorHeader)
                        }
                    }
                }
                .pageList()
                .refreshable { await catalog.refreshPoets() }
            } else if catalog.poetsFailed {
                ScrollView {
                    OfflineStateView { await catalog.refreshPoets() }
                }
            } else {
                LoadingPlaceholder(kind: .nameRows, count: 10)
                    .padding(.horizontal, Space.readingMargin)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.page)
        .navigationTitle("УсакӀуэхэр")
        .task { await catalog.loadPoets() }
        .onChange(of: catalog.poets, initial: true) { _, poets in group(poets ?? []) }
        .analyticsScreen(name: "AuthorsListView")
    }

    private func row(_ poet: Author, italic: Bool = false) -> some View {
        NavigationLink(value: Route.poet(poet)) {
            NameRowLabel(name: poet.name, italic: italic)
        }
        .contentRow()
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .serif(.indexLetter)
            .foregroundStyle(Palette.inkSecondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Space.readingMarginAX : Space.readingMargin)
            .padding(.top, Space.four)
            .padding(.bottom, Space.one)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.page)
            .listRowInsets(EdgeInsets())
    }

    private func group(_ poets: [Author]) {
        let known = poets.filter { KabardianText.searchKey($0.name) != Self.unknownName }
        unknown = poets.filter { KabardianText.searchKey($0.name) == Self.unknownName }
        let grouped = Dictionary(grouping: known) { KabardianAlphabet.sectionLetter(of: $0.name) }
        sections = grouped
            .map { LetterSection(letter: $0.key, poets: $0.value.sorted { KabardianAlphabet.precedes($0.name, $1.name) }) }
            .sorted { KabardianAlphabet.precedes($0.letter, $1.letter) }
    }
}
