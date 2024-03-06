//
//  RateManager.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 04.03.2024.
//

import SwiftUI

class RateManager {
    static var shared = RateManager()
    let url = "https://itunes.apple.com/app/id6478048644?action=write-review"

    private init() { }

    func rateApp() {
        guard let url = URL(string: url), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
