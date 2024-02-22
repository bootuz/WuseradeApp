//
//  MainView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        TabView(selection: .constant(1)) {
            PoemsListView().tabItem { Label("Усэхэр", systemImage: "pencil.and.scribble") }.tag(1)
            AuthorsListView().tabItem { Label("Усакlуэхэр", systemImage: "person.2") }.tag(2)
            LikedPoemsView().tabItem { Label("Сигу ирихьахэр", systemImage: "heart") }.tag(3)
        }
        .tint(.primary)
    }
}

#Preview {
    MainView()
}
