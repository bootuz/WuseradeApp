//
//  Endpoint.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

enum HTTPMethod: String {
    case DELETE
    case GET
    case PATCH
    case POST
    case PUT
}


protocol Endpoint {
    var scheme: String { get }
    var host: String { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var header: [String: String]? { get }
    var body: [String: Any]? { get }
    var query: [URLQueryItem]? { get }
    var urlRequest: URLRequest { get throws }
}

extension Endpoint {
    var scheme: String {
        return "https"
//        return "http"
    }

    var host: String {
        return "wuserade.onrender.com"
//        return "localhost"
    }

    var urlRequest: URLRequest {
        get throws {
            var urlComponents = URLComponents()
//            urlComponents.port = 8000
            urlComponents.scheme = scheme
            urlComponents.host = host
            urlComponents.path = path
            urlComponents.queryItems = query

            guard let url = urlComponents.url else {
                throw RequestError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            request.timeoutInterval = 20
            header?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if let body = body {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
            }
            return request
        }
    }
}


enum RequestError: Error {
    case decodeError(message: String)
    case notFound(message: String)
    case invalidURL
    case invalidResponse(message: String)
    case unexpectedStatusCodeError(statusCode: Int)
    case unknownError
}

extension RequestError: LocalizedError {

    var errorDescription: String? {
        switch self {
            case .decodeError(let message):
                return message
            case .invalidURL:
                return ""
            case .invalidResponse(let message):
                return message
            case .unexpectedStatusCodeError(let statusCode):
                return String(statusCode)
            case .notFound(let message):
                return message
            case .unknownError:
                return "Unknown error"
        }
    }
}
