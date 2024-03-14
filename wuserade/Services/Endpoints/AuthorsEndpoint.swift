//
//  AuthorsEndpoint.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import Foundation

enum AuthorsEndpoint {
    case fetchAuthors(page: Int)
    case fetchAuthor(id: Int)
    case poemsOfAuthor(id: Int)
    case authorsV2
}

extension AuthorsEndpoint: Endpoint {
    var path: String {
        switch self {
            case .fetchAuthors:
                return "/authors"
            case .fetchAuthor(let id):
                return "/authors/\(id)"
            case .poemsOfAuthor(let id):
                return "/authors/\(id)/poems"
            case .authorsV2:
                return "/authors/v2"
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
        switch self {
            case .fetchAuthors(let page):
                return [URLQueryItem(name: "page", value: String(page))]
            case .poemsOfAuthor:
                return nil
            case .fetchAuthor:
                return nil
            case .authorsV2:
                return nil
        }
    }
}
