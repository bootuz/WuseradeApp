//
//  OnboardingView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 29.02.2024.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("colorScheme") private var colorScheme: Bool = false
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
            .padding()

            VStack(alignment: .leading, spacing: 30) {
                AppFeature(
                    icon: "pencil.and.scribble",
                    title: "Адыгэ усэхэм зыщыгъэгъуазэ",
                    description: "Тхьэмахуэ къэс усэщlэ къыдогъувэ"
                )
                AppFeature(
                    icon: "book.pages",
                    title: "Усэхэр зытеухуам яхэплъэ",
                    description: "Зэмылlэужьыгъуэу диlэщ"
                )
                AppFeature(
                    icon: "person.2",
                    title: "Усакlуэхэр зэгъэцlыху",
                    description: "Я лэжьыгъэхэм нэlуасэ зыхуэщl"
                )
                AppFeature(
                    icon: "heart",
                    title: "Уигу ирихь усэхэр къыхэх",
                    description: "Уигу ирихьа усэхэм щхьэхуэу яхэплъэ"
                )
            }
            .padding()

            Spacer()
            
            Button(action: {
                firstLaunch = false
            }, label: {
                Text("Дэгъуэ")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(colorScheme ? .black : .white)
            })
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .padding()
        }
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
