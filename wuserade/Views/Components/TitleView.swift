//
//  TitleView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import SwiftUI

struct TitleView: View {
    var title: String

    init(title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title)
            .font(.custom("MarckScript-Regular", size: 25))
    }
}

#Preview {
    TitleView(title: "тхыпхъэр")
}
