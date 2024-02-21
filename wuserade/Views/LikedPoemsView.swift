//
//  LikedPoemsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI

struct LikedPoemsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(label: {
                Label("", systemImage: "heart.fill")
            }, description: {
                Text("Уигу ирихьа усэхэр мыбдежым къытридзэнущ")
                    .padding(.top, -15)
            })
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("уигу ирихьахэр")
                        .font(.custom("MarckScript-Regular", size: 25))
                }
            }
        }
    }
}

#Preview {
    LikedPoemsView()
}
