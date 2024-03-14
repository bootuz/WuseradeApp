//
//  AuthorsService.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import Foundation

protocol AuthorsServiceProtocol: Service where EndpointType == AuthorsEndpoint { }

class AuthorsService: AuthorsServiceProtocol {
    private var httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetch<T: Decodable>(_ endpoint: AuthorsEndpoint) async throws -> T {
        let (data, response) = try await httpClient.perform(request: endpoint.urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }
}
