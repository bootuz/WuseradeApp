//
//  SeletableTextView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 21.02.2024.
//

import SwiftUI

struct SelectableTextView: UIViewRepresentable {
    @EnvironmentObject var fontManager: FontSettingsManager
    var text: String
    var isEditable: Bool = false
    var isSelectable: Bool = true
    @Binding var height: CGFloat


    init(text: String, height: Binding<CGFloat>) {
        self.text = text
        self._height = height
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.text = text
        textView.isUserInteractionEnabled = true
        if fontManager.currentSettings.fontName == "System" {
            textView.font = UIFont.systemFont(ofSize: fontManager.currentSettings.fontSize)
        } else {
            textView.font = UIFont(name: fontManager.currentSettings.fontName, size: fontManager.currentSettings.fontSize)
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        if fontManager.currentSettings.fontName == "System" {
            uiView.font = UIFont.systemFont(ofSize: fontManager.currentSettings.fontSize)
        } else {
            uiView.font = UIFont(name: fontManager.currentSettings.fontName, size: fontManager.currentSettings.fontSize)
        }

        DispatchQueue.main.async {
            self.height = uiView.contentSize.height
        }

    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableTextView

        init(_ parent: SelectableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.height = textView.contentSize.height
            }
        }
    }
}
