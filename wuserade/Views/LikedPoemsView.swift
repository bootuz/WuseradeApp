//
//  LikedPoemsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI
import SwiftData
import SFSafeSymbols

struct LikedPoemsView: View {
    @Query(sort: \PersistedPoem.persistedDate, order: .reverse) private var persistedPoems: [PersistedPoem]

    var body: some View {
        NavigationStack {
            List {
                ForEach(persistedPoems) { persistedPoem in
                    PoemRow(poem: .toPoem(from: persistedPoem))
                }
            }
            .toolbarRole(.editor)
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if persistedPoems.isEmpty {
                    ContentUnavailableView(label: {
                        Label("Уигу ирихьа", systemSymbol: SFSymbol.heartFill)
                    }, description: {
                        Text("усэхэр мыбдеж къридзэнущ.")
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleView(title: "сигу ирихьахэр")
                }
            }
            .analyticsScreen(name: "LikedPoemsView")
        }
    }
}

#Preview {
    LikedPoemsView()
        .modelContainer(for: PersistedPoem.self, inMemory: true)
}
