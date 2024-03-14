//
//  Service.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 13.03.2024.
//

import Foundation


protocol Service {
    associatedtype EndpointType
    
    func fetch<T: Decodable>(_ endpoint: EndpointType) async throws -> T
}
