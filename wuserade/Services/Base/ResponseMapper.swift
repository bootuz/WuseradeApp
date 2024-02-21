//
//  ResponseMapper.swift
//  wuserade
//
//  Created by Астемир Бозиев on 15.02.2024.
//

import Foundation

struct ResponseMapper {
    static func map<T>(data: Data, response: HTTPURLResponse) throws -> T where T: Decodable {
        guard response.statusCode == 200 else {
            throw RequestError.invalidResponse(message: Constants.ErrorMessages.invalidResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let data = try? decoder.decode(T.self, from: data) else {
            throw RequestError.decodeError(message: "failed to decode response")
        }
        return data
    }
}
