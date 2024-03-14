//
//  CategoriesService.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation

protocol CategoriesServiceProtocol: Service where EndpointType == CategoriesEndpoint { }

class CategoriesService: CategoriesServiceProtocol {
    private var httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetch<T: Decodable>(_ endpoint: CategoriesEndpoint) async throws -> T {
        let (data, response) = try await httpClient.perform(request: endpoint.urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }
}
