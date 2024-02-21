//
//  PoemsService.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation


class PoemsService {
    private var httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchPoems(page: Int) async throws -> AllPoems {
        let (data, response) = try await httpClient.perform(request: PoemsEndpoint.fetchPoems(page: page).urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }

    func fetchPoem(by id: Int) async throws -> Poem {
        let (data, response) = try await httpClient.perform(request: PoemsEndpoint.fetchPoem(id: id).urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }

    func fetchLatestPoems() async throws -> [Poem] {
        let (data, response) = try await httpClient.perform(request: PoemsEndpoint.fetchLatestPoems.urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }

    func searchPoems(query: String) async throws -> [Poem] {
        let (data, response) = try await httpClient.perform(request: PoemsEndpoint.searchPoems(query: query).urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }
}
