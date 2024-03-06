//
//  ToastView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 06.03.2024.
//

import SwiftUI

struct ToastView: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    var style: ToastStyle
    var message: String
    var width = CGFloat.infinity
    var onCancelTapped: (() -> Void)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: style.iconFileName)
                .foregroundColor(style.themeColor)
            Text(message)
                .font(.caption)
                .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .padding(10)
        .frame(minWidth: 0, maxWidth: width)
        .background(colorScheme == .dark ? .black : .white)
        .cornerRadius(40)
        .padding(.horizontal, 16)
        .shadow(color: .gray.opacity(0.4), radius: 6)
    }
}

#Preview {
    ToastView(style: .copy, message: "Message") {}
}
