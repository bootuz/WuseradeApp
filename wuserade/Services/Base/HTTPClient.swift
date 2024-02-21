//
//  HTTPClient.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

protocol HTTPClient {
    func perform(request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPClient {

    func perform(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let method = request.httpMethod, let url = request.url {
            print("DEBUG: [\(method)] \(url)")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestError.invalidResponse(
                message: Constants.ErrorMessages.somethingWentWrong
            )
        }
        return (data, httpResponse)
    }
}
