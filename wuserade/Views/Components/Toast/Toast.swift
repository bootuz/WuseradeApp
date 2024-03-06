//
//  Toast.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 06.03.2024.
//

import Foundation

struct Toast: Equatable {
    var style: ToastStyle
    var message: String
    var duration: Double = 2
    var width: Double = .infinity
}
