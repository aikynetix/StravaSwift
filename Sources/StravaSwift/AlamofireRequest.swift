//
//  SwiftyJSONRequest.swift
//  StravaSwift
//
//  Created by Matthew on 15/11/2015.
//  Copyright © 2015 Matthew Clarkson. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

protocol JSONInitializable {
    init(_ json: JSON)
}

class MyObject: NSObject, JSONInitializable {
    var id: Int = 0
    var name: String = ""
    
    required init(_ json: JSON) {
        super.init()
        id = json["id"].intValue
        name = json["name"].stringValue
    }
}

class EVArrayResponseSerializer<T: NSObject>: DataResponseSerializerProtocol where T: JSONInitializable {
    typealias SerializedObject = [T]
    
    let keyPath: String?
    
    init(keyPath: String? = nil) {
        self.keyPath = keyPath
    }
    
    func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> [T] {
        if let error = error {
            throw error
        }
        
        guard let validData = data, validData.count > 0 else {
            throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
        }
        
        let jsonObject = try JSONSerialization.jsonObject(with: validData, options: .allowFragments)
        var json = JSON(jsonObject)
        
        if let keyPath = keyPath, !keyPath.isEmpty {
            json = json[keyPath]
        }
        
        guard let jsonArray = json.array else {
            let failureReason = "Expected JSON array but got: \(json)"
            throw AFError.responseSerializationFailed(reason: .jsonSerializationFailed(error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: failureReason])))
        }
        
        let objects = jsonArray.map { T($0) }
        return objects
    }
}

public protocol StravaModel {
    init(_ json: JSON)
}

public struct StravaSerializer<T: StravaModel>: DataResponseSerializerProtocol {
    public typealias SerializedObject = T
    let keyPath: String?
    
    public init(keyPath: String? = nil) {
        self.keyPath = keyPath
    }
    
    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> T {
        if let error = error { throw error }
        guard let validData = data, validData.count > 0 else {
            throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
        }
        let json = try JSON(data: validData)
        let targetJSON: JSON = {
            if let keyPath = keyPath, !keyPath.isEmpty {
                return json[keyPath]
            } else {
                return json
            }
        }()
        return T(targetJSON)
    }
}

public struct StravaArraySerializer<T: StravaModel>: DataResponseSerializerProtocol {
    public typealias SerializedObject = [T]
    let keyPath: String?
    
    public init(keyPath: String? = nil) {
        self.keyPath = keyPath
    }
    
    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> [T] {
        if let error = error { throw error }
        guard let validData = data, validData.count > 0 else {
            throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
        }
        let json = try JSON(data: validData)
        let targetJSON: JSON = {
            if let keyPath = keyPath, !keyPath.isEmpty {
                return json[keyPath]
            } else {
                return json
            }
        }()
        guard let jsonArray = targetJSON.array else {
            let reason = "Expected JSON array but got: \(targetJSON)"
            throw AFError.responseSerializationFailed(reason: .jsonSerializationFailed(error: NSError(domain: "StravaModel", code: 0, userInfo: [NSLocalizedDescriptionKey: reason])))
        }
        return jsonArray.map { T($0) }
    }
}

public extension DataRequest {
    
    @discardableResult
    func responseStrava<T: StravaModel>(queue: DispatchQueue? = nil,
                                        keyPath: String? = nil,
                                        completionHandler: @escaping (AFDataResponse<T>) -> Void) -> Self {
        return response(queue: queue ?? .main,
                        responseSerializer: StravaSerializer<T>(keyPath: keyPath),
                        completionHandler: completionHandler)
    }
    
    @discardableResult
    func responseStravaArray<T: StravaModel>(queue: DispatchQueue? = nil,
                                             keyPath: String? = nil,
                                             completionHandler: @escaping (AFDataResponse<[T]>) -> Void) -> Self {
        return response(queue: queue ?? .main,
                        responseSerializer: StravaArraySerializer<T>(keyPath: keyPath),
                        completionHandler: completionHandler)
    }
}
