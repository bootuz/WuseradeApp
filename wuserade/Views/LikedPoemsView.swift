//
//  LikedPoemsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI
import SwiftData

struct LikedPoemsView: View {
    @Query(sort: \PersistedPoem.persistedDate, order: .reverse) private var poems: [PersistedPoem]

    var body: some View {
        NavigationStack {
            List {
                ForEach(poems) { poem in
                    let poem: Poem = .toPoem(from: poem)
                    NavigationLink {
                        PoemView(viewModel: PoemViewModel(poem: poem))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(poem.title)
                                .lineLimit(0)
                            Text(poem.author.name)
                                .foregroundStyle(.secondary)
                                .italic()
                                .fontDesign(.serif)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if poems.isEmpty {
                    ContentUnavailableView(label: {
                        Label("", systemImage: "heart.fill")
                    }, description: {
                        Text("Уигу ирихьа усэхэр мыбдежым къытридзэнущ")
                            .padding(.top, -15)
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("сигу ирихьахэр")
                        .font(.custom("MarckScript-Regular", size: 25))
                }
            }
        }
    }
}

#Preview {
    LikedPoemsView()
        .modelContainer(for: PersistedPoem.self, inMemory: true)
}
