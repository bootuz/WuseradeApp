//
//  CategoriesEndpoint.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation

enum PoemCategoriesEndpoint {
    case fetchCategories
    case fetchPoemsByCategory(id: Int)
}

extension PoemCategoriesEndpoint: Endpoint {
    var path: String {
        switch self {
            case .fetchCategories:
                return "/themes"
            case .fetchPoemsByCategory(let id):
                return "/themes/\(id)/poems"
        }
    }

    var method: HTTPMethod {
        return .GET
    }

    var header: [String : String]? {
        return nil
    }

    var body: [String : Any]? {
        return nil
    }

    var query: [URLQueryItem]? {
        return nil
    }
}
