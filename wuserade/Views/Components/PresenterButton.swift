//
//  SettingsPresenterButton.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

struct PresenterButton<Destination: View>: View {
    let destination: () -> Destination
    let systemImageName: String

    @State private var showDestinationView: Bool = false
    @AppStorage("colorScheme") private var colorScheme: Bool = false

    var body: some View {
        Button {
            showDestinationView.toggle()
        } label: {
            Image(systemName: systemImageName)
        }
        .sheet(isPresented: $showDestinationView, content: {
            destination()
                .preferredColorScheme(colorScheme ? .dark : .light)
        })
    }
}

#Preview {
    PresenterButton()
}
