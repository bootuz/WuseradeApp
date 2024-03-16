//
//  CopyButton.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 08.03.2024.
//

import SwiftUI

struct CopyButton<Item: Copyable>: View {
    @Binding var toast: Toast?
    @State var buttonTapped = false
    private let pasteboard = UIPasteboard.general
    let item: Item

    init(for item: Item, toast: Binding<Toast?>) {
        self.item = item
        _toast = toast
    }

    var body: some View {
        Button(action: {
            pasteboard.string = item.copyableText
            buttonTapped.toggle()
            showToast()
        }, label: {
            Image(systemName: "doc.on.doc")
        })
        .sensoryFeedback(.success, trigger: buttonTapped)
    }

    private func showToast() {
        withAnimation {
            toast = Toast(style: .copy, message: "Копие тепхащ", width: 160)
        }
    }
}

protocol Copyable {
    var copyableText: String { get }
}

#Preview {
    CopyButton(for: Poem.example, toast: .constant(Toast(style: .copy, message: "test")))
}
