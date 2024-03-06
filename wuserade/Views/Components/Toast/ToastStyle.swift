//
//  ToastStyle.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 06.03.2024.
//
import SwiftUI

enum ToastStyle {
    case error
    case warning
    case success
    case copy
}

extension ToastStyle {
    var themeColor: Color {
        switch self {
            case .error: return .red
            case .warning: return .orange
            case .copy: return .green
            case .success: return .green
        }
    }

    var iconFileName: String {
        switch self {
            case .copy: return "doc.on.doc.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
        }
    }
}
