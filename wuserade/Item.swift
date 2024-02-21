//
//  Item.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
