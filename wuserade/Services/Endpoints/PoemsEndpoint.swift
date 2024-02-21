//
//  PoemsEndpoint.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

enum PoemsEndpoint {
    case fetchPoems(page: Int)
    case fetchPoem(id: Int)
    case fetchLatestPoems
    case searchPoems(query: String)
}

extension PoemsEndpoint: Endpoint {
    var path: String {
        switch self {
            case .fetchPoems:
                return "/poems"
            case .fetchPoem(let id):
                return "/poems/\(id)"
            case .fetchLatestPoems:
                return "/poems/latest"
            case .searchPoems:
                return "/poems/search"
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
            case .fetchPoems(let page):
                return [URLQueryItem(name: "page", value: String(page))]
            case .searchPoems(let query):
                return [URLQueryItem(name: "q", value: query)]
            default:
                return nil
        }
    }
}
