//
//  TestView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 17.02.2024.
//

import SwiftUI

struct SearchBarView: View {

    @Binding var input: String

    var body: some View {
        HStack(spacing: .zero) {
            HStack(spacing: .zero) {
                Image(systemName: "magnifyingglass")
                    .padding(5)

                TextField("Search Fighters", text: $input)
                    .onChange(of: input, {

                    })
            }
            .background(.white)
            .cornerRadius(20)

            Spacer()

            if !input.isEmpty {
                Button("Cancel") {
                    withAnimation {
                        input = ""
                    }
                }
                .tint(.black)
                .font(.body)
                .padding(.leading, 10)
            }
        }
        .padding(15)
    }
}


#Preview {
    SearchBarView(input: .constant(""))
}
