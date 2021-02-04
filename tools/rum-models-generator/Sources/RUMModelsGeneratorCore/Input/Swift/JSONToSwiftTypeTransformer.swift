/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Transforms `JSONObject` schema into `SwiftStruct` schema.
internal class JSONToSwiftTypeTransformer {
    func transform(jsonObjects: [JSONObject]) throws -> [SwiftStruct] {
        return try jsonObjects.map { try transform(jsonObject: $0) }
    }

    private func transform(jsonObject: JSONObject) throws -> SwiftStruct {
        var `struct` = try transformJSONToStruct(jsonObject)
        `struct` = resolveTransitiveMutableProperties(in: `struct`)
        return `struct`
    }

    // MARK: - Transforming ambiguous types

    private func transformJSONToAnyType(_ json: JSONType) throws -> SwiftType {
        switch json {
        case let jsonPrimitive as JSONPrimitive:
            return transformJSONtoPrimitive(jsonPrimitive)
        case let jsonArray as JSONArray:
            return try transformJSONToArray(jsonArray)
        case let jsonEnumeration as JSONEnumeration:
            return transformJSONToEnum(jsonEnumeration)
        case let jsonObject as JSONObject:
            return try transformJSONToStruct(jsonObject)
        default:
            throw Exception.unimplemented("Transforming \(json) into `SwiftType` is not supported.")
        }
    }

    // MARK: - Transforming concrete types

    private func transformJSONtoPrimitive(_ jsonPrimitive: JSONPrimitive) -> SwiftPrimitiveType {
        switch jsonPrimitive {
        case .bool: return SwiftPrimitive<Bool>()
        case .double: return SwiftPrimitive<Double>()
        case .integer: return SwiftPrimitive<Int>()
        case .string: return SwiftPrimitive<String>()
        }
    }

    private func transformJSONToArray(_ jsonArray: JSONArray) throws -> SwiftArray {
        return SwiftArray(element: try transformJSONToAnyType(jsonArray.element))
    }

    private func transformJSONToEnum(_ jsonEnumeration: JSONEnumeration) -> SwiftEnum {
        return SwiftEnum(
            name: jsonEnumeration.name,
            comment: jsonEnumeration.comment,
            cases: jsonEnumeration.values.map { value in
                SwiftEnum.Case(label: value, rawValue: value)
            },
            conformance: []
        )
    }

    private func transformJSONToStruct(_ jsonObject: JSONObject) throws -> SwiftStruct {
        /// Reads Struct property default value.
        func readDefaultValue(for objectProperty: JSONObject.Property) throws -> SwiftPropertyDefaultValue? {
            return objectProperty.defaultValue.ifNotNil { value in
                switch value {
                case .integer(let intValue):
                    return intValue
                case .string(let stringValue):
                    if objectProperty.type is JSONEnumeration {
                        return SwiftEnum.Case(label: stringValue, rawValue: stringValue)
                    } else {
                        return stringValue
                    }
                }
            }
        }

        /// Reads Struct properties.
        func readProperties(from objectProperties: [JSONObject.Property]) throws -> [SwiftStruct.Property] {
            return try objectProperties.map { jsonProperty in
                return SwiftStruct.Property(
                    name: jsonProperty.name,
                    comment: jsonProperty.comment,
                    type: try transformJSONToAnyType(jsonProperty.type),
                    isOptional: !jsonProperty.isRequired,
                    isMutable: !jsonProperty.isReadOnly,
                    defaultValue: try readDefaultValue(for: jsonProperty),
                    codingKey: jsonProperty.name
                )
            }
        }

        /// Reads Struct properties.
        func readAdditionalProperties(from objectAdditionalProperties: JSONObject.Property?) throws -> SwiftStruct.Property? {
            guard let additionalProperties = objectAdditionalProperties else { return nil }
            return SwiftStruct.Property(
                    name: additionalProperties.name,
                    comment: additionalProperties.comment,
                    type: try transformJSONToAnyType(additionalProperties.type),
                    isOptional: !additionalProperties.isRequired,
                    isMutable: !additionalProperties.isReadOnly,
                    defaultValue: try readDefaultValue(for: additionalProperties),
                    codingKey: additionalProperties.name
                )
        }

        return SwiftStruct(
            name: jsonObject.name,
            comment: jsonObject.comment,
            properties: try readProperties(from: jsonObject.properties),
            additionalProperties: try readAdditionalProperties(from: jsonObject.additionalProperties),
            conformance: []
        )
    }

    // MARK: - Resolving transitive mutable properties

    /// Looks recursively into given `struct` and changes mutability
    /// signatures in properties referencing structs with mutable properties.
    ///
    /// For example, receiving such structure as input:
    ///
    ///         struct Foo {
    ///             struct Bar {
    ///                 let bizz: String
    ///                 var buzz: String // ⚠️ this can't be mutated as `bar` is immutable
    ///             }
    ///             let bar: Bar
    ///         }
    ///
    /// it transforms the `bar` property mutability signature from `let` to `var` to allow modification of `buzz` property:
    ///
    ///         struct Foo {
    ///             struct Bar {
    ///                 let bizz: String
    ///                 var buzz: String
    ///             }
    ///             var bar: Bar // 💫 fix, now `bar.buzz` can be mutated
    ///         }
    ///
    private func resolveTransitiveMutableProperties(in `struct`: SwiftStruct) -> SwiftStruct {
        var `struct` = `struct`

        `struct`.properties = `struct`.properties.map { property in
            var property = property
            property.isMutable = property.isMutable || hasTransitiveMutableProperty(type: property.type)

            if let nestedStruct = property.type as? SwiftStruct {
                property.type = resolveTransitiveMutableProperties(in: nestedStruct)
            }

            return property
        }

        return `struct`
    }

    /// Returns `true` if the given `SwiftType` contains a mutable property (`var`) or any of its nested types does.
    private func hasTransitiveMutableProperty(type: SwiftType) -> Bool {
        switch type {
        case let array as SwiftArray:
            return hasTransitiveMutableProperty(type: array.element)
        case let `struct` as SwiftStruct:
            return `struct`.properties.contains { property in
                property.isMutable || hasTransitiveMutableProperty(type: property.type)
            }
        default:
            return false
        }
    }
}
