//
//  FontSettingsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 22.02.2024.
//

import SwiftUI

struct FontSettingsView: View {
    @ObservedObject var fontManager: FontSettingsManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            VStack {
                Form {
                    Section(header: Text("")) {
                        Picker("Тхыпхъэр", selection: $fontManager.currentSettings.fontName) {
                            Text("System").tag("System")
                            Text("MarckScript").tag("MarckScript-Regular")
                                .font(.custom("MarckScript-Regular", size: 18))
                            Text("Georgia").tag("Georgia")
                            Text("Times New Roman").tag("Times New Roman")
                        }
                        HStack {
                            Slider(value: $fontManager.currentSettings.fontSize, in: 10...30, step: 1)
                            Text("\(Int(fontManager.currentSettings.fontSize)) pt")
                                .frame(width: 50)
                        }
                    }
                }
//                .padding(.top, -50)
            }
            .frame(height: 150)

            PoemExampleView()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Тхыпхъэр")
                    .font(.custom("MarckScript-Regular", size: 25))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    dismiss()
                }, label: {
                    Image(systemName: "checkmark")
                })
            }
        }
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)

    }

    private func PoemExampleView() -> some View {
        VStack(alignment: .center) {
            VStack(alignment: .center) {
                Text(Poem.example.title)
                    .font(.custom(fontManager.currentSettings.fontName, size: 30))
                    .multilineTextAlignment(.center)
                Text(Poem.example.author.name)
                    .font(.custom(fontManager.currentSettings.fontName, size: 18))
                    .italic()
                    .padding(.vertical, 1)

                Divider()
            }
            .padding(.bottom, 10)

            HStack {
                SelectableTextView(text: Poem.example.content, height: .constant(0))
//                    .frame(height: 300)
                Spacer()
            }
        }
        .padding()
    }
}

#Preview {
    FontSettingsView(fontManager: FontSettingsManager())

}
