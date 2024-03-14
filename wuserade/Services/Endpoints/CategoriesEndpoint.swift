//
//  CategoriesEndpoint.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation

enum CategoriesEndpoint {
    case categories
    case poemsByCategory(id: Int)
}

extension CategoriesEndpoint: Endpoint {
    var path: String {
        switch self {
            case .categories:
                return "/themes"
            case .poemsByCategory(let id):
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
