//
//  AuthorsService.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import Foundation

class AuthorsService {
    private var httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchAuthors() async throws -> [Author] {
        let (data, response) = try await httpClient.perform(request: AuthorsEndpoint.fetchAuthorsV2.urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }

    func fetchAuthor(id: Int) async throws -> Author {
        let (data, response) = try await httpClient.perform(request: AuthorsEndpoint.fetchAuthor(id: id).urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }

    func fetchPoemsOfAuthor(id: Int, page: Int) async throws -> [Poem] {
        let (data, response) = try await httpClient.perform(request: AuthorsEndpoint.fetchPoemsOfAuthor(id: id, page: page).urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }
}
