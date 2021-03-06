//
//  JSONDecoder.swift
//  Alter
//
//  Created by 林 達也 on 2017/04/20.
//  Copyright © 2017年 sora0077. All rights reserved.
//

import Foundation

private typealias JSONDictionary = [String: Any]
private typealias JSONArray = [Any]

struct JSONDecoder: Decoder {
    private enum Data {
        case dictionary(JSONDictionary)
        case array(JSONArray)
        case value(Any)

        var rawValue: Any {
            switch self {
            case .dictionary(let dictionary): return dictionary
            case .array(let array): return array
            case .value(let value): return value
            }
        }
    }
    var rawValue: Any { return data.rawValue }
    private let data: Data
    fileprivate init(_ any: Any) {
        switch any {
        case let dictionary as JSONDictionary:
            data = .dictionary(dictionary)
        case let array as JSONArray:
            data = .array(array)
        default:
            data = .value(any)
        }
    }
    init(_ any: Any, rootKeyPath: KeyPath?) throws {
        switch (any, rootKeyPath) {
        case (let data as Foundation.Data, _):
            try self.init(JSONSerialization.jsonObject(with: data, options: .allowFragments), rootKeyPath: rootKeyPath)
        case (_, let keyPath?) where !keyPath.isEmpty:
            guard let v = try value(for: keyPath, from: any) else {
                throw DecodeError.missingKeyPath(keyPath)
            }
            self.init(v)
        default:
            self.init(any)
        }
    }

    fileprivate func optionalValue(forKeyPath keyPath: KeyPath) throws -> Any? {
        return try optional(value(for: keyPath, from: rawValue)) { (error) in
            switch error {
            case .missingKeyPath(let missing) where keyPath == missing: return true
            default: return false
            }
        }
    }
}

/// decode for value
extension JSONDecoder {
    private func _decode<T>(forKeyPath keyPath: KeyPath) throws -> T? where T: Decodable {
        guard let v = try optionalValue(forKeyPath: keyPath) else {
            return nil
        }
        return try wrapError(for: keyPath, value: try T.decode(JSONDecoder(v)))
    }

    func decode<T>(forKeyPath keyPath: KeyPath) throws -> T where T: Decodable {
        guard let value: T = try _decode(forKeyPath: keyPath) else {
            throw DecodeError.missingKeyPath(keyPath)
        }
        return value
    }

    func decode(forKeyPath keyPath: KeyPath) throws -> Any {
        guard let v = try optionalValue(forKeyPath: keyPath) else {
            throw DecodeError.missingKeyPath(keyPath)
        }
        return v
    }
}

/// decode for array
extension JSONDecoder {
    private func _decode<T>(forKeyPath keyPath: KeyPath) throws -> [T?]? where T: Decodable {
        guard let array = try optionalValue(forKeyPath: keyPath) as? [Any?] else {
            return nil
        }
        return try wrapError(for: keyPath, value: try array.map {
            try $0.map(JSONDecoder.init).map(T.decode)
        })
    }

    func decode<T>(forKeyPath keyPath: KeyPath) throws -> [T?] where T: Decodable {
        guard let array: [T?] = try _decode(forKeyPath: keyPath) else {
            throw DecodeError.missingKeyPath(keyPath)
        }
        return array
    }
}

/// decode for dictionary
extension JSONDecoder {
    private func _decode<T>(forKeyPath keyPath: KeyPath) throws -> [String: T?]? where T: Decodable {
        guard let dictionary = try optionalValue(forKeyPath: keyPath) as? [String: Any?] else {
            return nil
        }
        return try wrapError(for: keyPath, value: try dictionary.map {
            try $0.map(JSONDecoder.init).map(T.decode)
        })
    }

    func decode<T>(forKeyPath keyPath: KeyPath) throws -> [String : T?] where T : Decodable {
        guard let dictionary: [String: T?] = try _decode(forKeyPath: keyPath) else {
            throw DecodeError.missingKeyPath(keyPath)
        }
        return dictionary
    }
}

#if os(macOS)
    extension JSONDecoder {
        func decode<T>(forKeyPath keyPath: KeyPath, optional: Bool) throws -> T? where T: Decodable {
            do {
                return try decode(forKeyPath: keyPath)
            } catch DecodeError.missingKeyPath(let missing) where checkOptional(missing: missing, for: keyPath) {
                return nil
            }
        }
    }
#endif

// MARK: - util
private func optional<T>(_ value: @autoclosure () throws -> T?, _ cond: (DecodeError) -> Bool) rethrows -> T? {
    do {
        return try value()
    } catch let error as DecodeError where cond(error) {
        return nil
    }
}

private func wrapError<T>(for keyPath: KeyPath, value: @autoclosure () throws -> T) throws -> T {
    do {
        return try value()
    } catch let DecodeError.missingKeyPath(missing) {
        throw DecodeError.missingKeyPath(keyPath + missing)
    } catch let DecodeError.typeMismatch(expected, actual, mismatched) {
        throw DecodeError.typeMismatch(expected: expected, actual: actual, keyPath: keyPath + mismatched)
    }
}

private extension KeyPath.Component {
    var expectedType: Any.Type {
        switch self {
        case .key: return JSONDictionary.self
        case .index: return JSONArray.self
        }
    }
}

private func value(for keyPath: KeyPath, from json: Any) throws -> Any? {  // swiftlint:disable:this cyclomatic_complexity
    var result: Any? = json
    var reached: [KeyPath.Component] = []
    for key in keyPath {
        defer { reached.append(key) }
        switch (result, key) {
        case (let dict as JSONDictionary, .key(let key)):
            result = dict[key]
        case (let array as JSONArray, .index(let index)):
            result = array.indices.contains(index) ? array[index] : nil
        case (is JSONDictionary, .index):
            throw DecodeError.typeMismatch(expected: JSONArray.self, actual: result, keyPath: keyPath)
        case (is JSONArray, .key):
            throw DecodeError.typeMismatch(expected: JSONDictionary.self, actual: result, keyPath: keyPath)
        case (nil, _):
            throw DecodeError.missingKeyPath(KeyPath(reached))
        default:
            throw DecodeError.typeMismatch(expected: key.expectedType, actual: result, keyPath: KeyPath(reached + [key]))
        }
    }
    switch result {
    case is NSNull, nil:
        return nil
    case let value?:
        return value
    }
}
