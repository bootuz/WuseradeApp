//
//  CategoriesService.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 23.02.2024.
//

import Foundation

class PoemCategoriesService {
    private var httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchCategories() async throws -> [PoemCategory] {
        let (data, response) = try await httpClient.perform(request: PoemCategoriesEndpoint.fetchCategories.urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }

    func fetchPoemsByCategory(id: Int) async throws -> [Poem] {
        let (data, response) = try await httpClient.perform(request: PoemCategoriesEndpoint.fetchPoemsByCategory(id: id).urlRequest)
        return try ResponseMapper.map(data: data, response: response)
    }
}
