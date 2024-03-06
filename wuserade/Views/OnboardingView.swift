//
//  OnboardingView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 29.02.2024.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @AppStorage("firstLaunch") private var firstLaunch = true

    var body: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .center) {
                    Text("Къеблагъэ Усэрадэм!")
                        .font(.system(size: 50, weight: .heavy))
                }
            }

            VStack(alignment: .leading, spacing: 30) {
                AppFeature(
                    icon: "pencil.and.scribble",
                    title: "Адыгэ усыгъэм хэгъуазэ",
                    description: "Тхьэмахуэ къэс усэщӏэ къыдогъэувэ"
                )
                AppFeature(
                    icon: "book.pages",
                    title: "Усэхэр зытеухуам еплъ",
                    description: "Зэмылӏэужыгъуэу къыхэтхащ"
                )
                AppFeature(
                    icon: "person.2",
                    title: "Усакӏуэхэр зэгъэцӏыху",
                    description: "Я лэжьыгъэхэм нэlуасэ зыхуэщl"
                )
                AppFeature(
                    icon: "heart",
                    title: "Уигу ирихь усэхэр къыхэх",
                    description: "Къыхэпхам щхьэхуэу яхэплъэж"
                )
            }

            Spacer()
            
            Button(action: {
                firstLaunch = false
            }, label: {
                Text("Хъуащ")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
            })
            .buttonStyle(.borderedProminent)
            .tint(.primary)
        }
        .padding()
    }
    
    @ViewBuilder
    private func AppFeature(icon: String, title: String, description: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 30))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading) {
                Text(title)
                    .bold()
                Text(description)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
