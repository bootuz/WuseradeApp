//
//  SettingsPresenterButton.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

struct PresenterButton<Label, Destination>: View where Label : View, Destination : View {

    enum PresentationType {
        case sheet
        case fullScreen
        case popover
    }

    let destination: Destination
    let label: Label
    let presentationType: PresentationType

    @State private var showDestinationView: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    init(presentationType: PresentationType, @ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.presentationType = presentationType
        self.destination = destination()
        self.label = label()
    }

    var body: some View {
        Button {
            showDestinationView.toggle()
        } label: {
            label
        }
        .sheet(isPresented: Binding(
            get: { showDestinationView && presentationType == .sheet },
            set: { newValue in
                    if !newValue {
                        showDestinationView = false
                    }
                }
            ), content: {
                destination
                    .preferredColorScheme(colorScheme)
        })
        .fullScreenCover(isPresented: Binding(
            get: { showDestinationView && presentationType == .fullScreen },
            set: { newValue in
                if !newValue {
                    showDestinationView = false
                }
            }
        ), content: {
            destination
                .preferredColorScheme(colorScheme)
        })
        .popover(isPresented: Binding(
            get: { showDestinationView && presentationType == .popover },
            set: { newValue in
                if !newValue {
                    showDestinationView = false
                }
            }
        ), content: {
            destination
                .preferredColorScheme(colorScheme)
        })
    }
}

#Preview {
    PresenterButton(presentationType: .fullScreen, destination: {
        SettingsView()
    }, label: {
        Image(systemName: "gearshape")
    })
    .tint(.primary)
}
