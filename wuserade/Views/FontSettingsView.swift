//
//  FontSettingsView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 22.02.2024.
//

import SwiftUI
import SFSafeSymbols

struct FontSettingsView: View {
    @EnvironmentObject var fontManager: FontSettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var setDefaultTapped: Bool = false
    var body: some View {
        VStack {
            PoemExampleView()
            Form {
                Section("Теплъэр") {
                    Picker(selection: $fontManager.currentSettings.fontName) {
                        Text("System").tag("System")
                        Text("MarckScript").tag("MarckScript-Regular")
                        Text("Georgia").tag("Georgia")
                        Text("Times New Roman").tag("Times New Roman")
                    } label: {
                        HStack {
                            Text("Aa")
                                .font(.custom(fontManager.currentSettings.fontName, size: 18))
                                .padding(.trailing, 10)
                            Text("Тхыпхъэр")
                        }
                    }

                    Stepper(value: $fontManager.currentSettings.fontSize, in: 10...30, step: 1) {
                        Label("Инагъыр: \(Int(fontManager.currentSettings.fontSize))", systemSymbol: SFSymbol.textformatSize)
                    }

                    Toggle(isOn: $fontManager.currentSettings.isBold) {
                        Label("Пlащэу", systemSymbol: SFSymbol.bold)
                    }
                    .tint(.green)
                }

                Section("") {
                    HStack {
                        Image(systemSymbol: SFSymbol.arrowUpAndDownTextHorizontal)
                        Slider(value: $fontManager.currentSettings.lineSpacing, in: 0...10, step: 0.25) {
                        } minimumValueLabel: {
                            Text("")
                                .frame(width: 0)
                        } maximumValueLabel: {
                            Text(String(format: "%.2f", fontManager.currentSettings.lineSpacing))
                                .frame(width: 45)
                        }
                    }

                    VStack {
                        HStack {
                            VStack(alignment: .center) {
                                Text("abc")
                                    .font(.system(size: 13))
                                Image(systemSymbol: SFSymbol.arrowLeftAndRight)
                                    .font(.system(size: 16))
                            }
                            .padding(.horizontal, 4)

                            Slider(value: $fontManager.currentSettings.characterSpacing, in: -2...2, step: 0.20) {

                            } minimumValueLabel: {
                                Text("")
                                    .frame(width: 0)
                            } maximumValueLabel: {
                                Text(String(format: "%.2f", fontManager.currentSettings.characterSpacing))
                                    .frame(width: 45)
                            }
                        }
                    }
                }
                Button(action: {
                    fontManager.setToDefaultSettings()
                    setDefaultTapped.toggle()
                }, label: {
                    Text("Зэрыщытам хуэгъэкlуэжын")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.red)
                })
                .sensoryFeedback(.impact(weight: .heavy), trigger: setDefaultTapped)
            }
            .frame(height: 430)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TitleView(title: "текстыр")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    dismiss()
                }, label: {
                    Image(systemSymbol: SFSymbol.checkmark)
                })
            }
        }
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen(name: "FontSettingsView")
    }

    private func PoemExampleView() -> some View {
        VStack(alignment: .center) {
            PoemHeaderView(poem: Poem.example)
                .disabled(true)

            HStack {
                PoemTextView(text: Poem.example.content)
                Spacer()
            }
            Spacer()
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        FontSettingsView()
            .environmentObject(FontSettingsManager())
            .tint(.primary)
    }
}
