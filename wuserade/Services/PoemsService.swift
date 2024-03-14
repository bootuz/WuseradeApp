//
//  PoemsService.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

protocol PoemsServiceProtocol: Service where EndpointType == PoemsEndpoint { }

class PoemsService: PoemsServiceProtocol {
    private var httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetch<T: Decodable>(_ endpoint: PoemsEndpoint) async throws -> T {
        let (data, response) = try await httpClient.perform(request: endpoint.urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }
}
