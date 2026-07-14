//
//  MsgpackValue.swift
//  IceNomad
//
//  A minimal MessagePack encoder/decoder — just enough of the spec to
//  interoperate with LXMF, which uses msgpack for announce app_data
//  (display name/stamp cost/features) and for its own message payload
//  (timestamp/content/title/fields). Not a general-purpose msgpack
//  library — covers nil, bool, integers, doubles, strings, binary,
//  arrays, and maps, which is everything LXMF actually uses.
//

import Foundation

indirect enum MsgpackValue {

    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case binary(Data)
    case array([MsgpackValue])
    case map([(MsgpackValue, MsgpackValue)])
}


enum MsgpackError: Error {
    case unexpectedEndOfData
    case unsupportedType(UInt8)
}


// MARK: - Decoding

extension MsgpackValue {

    /// Decodes a single value starting at `offset`, advancing `offset`
    /// past what it consumed. Throws rather than crashing on malformed
    /// input, since this will run on data from the open network.
    static func decode(_ data: Data, offset: inout Data.Index) throws -> MsgpackValue {

        guard offset < data.endIndex else {
            throw MsgpackError.unexpectedEndOfData
        }

        let byte = data[offset]
        offset = data.index(after: offset)

        switch byte {

        case 0x00...0x7f:
            return .int(Int64(byte))

        case 0xe0...0xff:
            return .int(Int64(Int8(bitPattern: byte)))

        case 0xc0:
            return .null

        case 0xc2:
            return .bool(false)

        case 0xc3:
            return .bool(true)

        case 0xca: // float32
            let bits = try readUInt32(data, &offset)
            return .double(Double(Float(bitPattern: bits)))

        case 0xcb: // float64
            let bits = try readUInt64(data, &offset)
            return .double(Double(bitPattern: bits))

        case 0xcc: // uint8
            return .int(Int64(try readUInt8(data, &offset)))

        case 0xcd: // uint16
            return .int(Int64(try readUInt16(data, &offset)))

        case 0xce: // uint32
            return .int(Int64(try readUInt32(data, &offset)))

        case 0xcf: // uint64
            return .int(Int64(bitPattern: try readUInt64(data, &offset)))

        case 0xd0: // int8
            return .int(Int64(Int8(bitPattern: try readUInt8(data, &offset))))

        case 0xd1: // int16
            return .int(Int64(Int16(bitPattern: try readUInt16(data, &offset))))

        case 0xd2: // int32
            return .int(Int64(Int32(bitPattern: try readUInt32(data, &offset))))

        case 0xd3: // int64
            return .int(Int64(bitPattern: try readUInt64(data, &offset)))

        case 0xa0...0xbf: // fixstr
            let length = Int(byte & 0x1f)
            return .string(try readString(data, &offset, length: length))

        case 0xd9: // str8
            let length = Int(try readUInt8(data, &offset))
            return .string(try readString(data, &offset, length: length))

        case 0xda: // str16
            let length = Int(try readUInt16(data, &offset))
            return .string(try readString(data, &offset, length: length))

        case 0xdb: // str32
            let length = Int(try readUInt32(data, &offset))
            return .string(try readString(data, &offset, length: length))

        case 0xc4: // bin8
            let length = Int(try readUInt8(data, &offset))
            return .binary(try readBytes(data, &offset, length: length))

        case 0xc5: // bin16
            let length = Int(try readUInt16(data, &offset))
            return .binary(try readBytes(data, &offset, length: length))

        case 0xc6: // bin32
            let length = Int(try readUInt32(data, &offset))
            return .binary(try readBytes(data, &offset, length: length))

        case 0x90...0x9f: // fixarray
            let count = Int(byte & 0x0f)
            return .array(try readArray(data, &offset, count: count))

        case 0xdc: // array16
            let count = Int(try readUInt16(data, &offset))
            return .array(try readArray(data, &offset, count: count))

        case 0xdd: // array32
            let count = Int(try readUInt32(data, &offset))
            return .array(try readArray(data, &offset, count: count))

        case 0x80...0x8f: // fixmap
            let count = Int(byte & 0x0f)
            return .map(try readMap(data, &offset, count: count))

        case 0xde: // map16
            let count = Int(try readUInt16(data, &offset))
            return .map(try readMap(data, &offset, count: count))

        case 0xdf: // map32
            let count = Int(try readUInt32(data, &offset))
            return .map(try readMap(data, &offset, count: count))

        default:
            throw MsgpackError.unsupportedType(byte)
        }
    }


    /// Convenience: decode the first (and typically only, for our uses)
    /// top-level value in a blob.
    static func decode(_ data: Data) throws -> MsgpackValue {
        var offset = data.startIndex
        return try decode(data, offset: &offset)
    }


    // MARK: - Read helpers

    private static func readUInt8(_ data: Data, _ offset: inout Data.Index) throws -> UInt8 {
        guard offset < data.endIndex else { throw MsgpackError.unexpectedEndOfData }
        let value = data[offset]
        offset = data.index(after: offset)
        return value
    }

    private static func readUInt16(_ data: Data, _ offset: inout Data.Index) throws -> UInt16 {
        let bytes = try readBytes(data, &offset, length: 2)
        return bytes.withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    private static func readUInt32(_ data: Data, _ offset: inout Data.Index) throws -> UInt32 {
        let bytes = try readBytes(data, &offset, length: 4)
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    private static func readUInt64(_ data: Data, _ offset: inout Data.Index) throws -> UInt64 {
        let bytes = try readBytes(data, &offset, length: 8)
        return bytes.withUnsafeBytes { $0.load(as: UInt64.self) }.bigEndian
    }

    private static func readBytes(_ data: Data, _ offset: inout Data.Index, length: Int) throws -> Data {
        guard let end = data.index(offset, offsetBy: length, limitedBy: data.endIndex) else {
            throw MsgpackError.unexpectedEndOfData
        }
        let bytes = Data(data[offset..<end])
        offset = end
        return bytes
    }

    private static func readString(_ data: Data, _ offset: inout Data.Index, length: Int) throws -> String {
        let bytes = try readBytes(data, &offset, length: length)
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    private static func readArray(_ data: Data, _ offset: inout Data.Index, count: Int) throws -> [MsgpackValue] {
        var result: [MsgpackValue] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try decode(data, offset: &offset))
        }
        return result
    }

    private static func readMap(_ data: Data, _ offset: inout Data.Index, count: Int) throws -> [(MsgpackValue, MsgpackValue)] {
        var result: [(MsgpackValue, MsgpackValue)] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            let key = try decode(data, offset: &offset)
            let value = try decode(data, offset: &offset)
            result.append((key, value))
        }
        return result
    }
}


// MARK: - Encoding

extension MsgpackValue {

    func encode() -> Data {

        switch self {

        case .null:
            return Data([0xc0])

        case .bool(let value):
            return Data([value ? 0xc3 : 0xc2])

        case .int(let value):
            return Self.encodeInt(value)

        case .double(let value):
            var bits = value.bitPattern.bigEndian
            return Data([0xcb]) + Data(bytes: &bits, count: 8)

        case .string(let value):
            return Self.encodeStringOrBinary(Data(value.utf8), isString: true)

        case .binary(let value):
            return Self.encodeStringOrBinary(value, isString: false)

        case .array(let values):
            var result = Self.encodeArrayHeader(count: values.count)
            for value in values {
                result.append(value.encode())
            }
            return result

        case .map(let pairs):
            var result = Self.encodeMapHeader(count: pairs.count)
            for (key, value) in pairs {
                result.append(key.encode())
                result.append(value.encode())
            }
            return result
        }
    }


    private static func encodeInt(_ value: Int64) -> Data {

        if value >= 0 && value <= 0x7f {
            return Data([UInt8(value)])
        }

        if value < 0 && value >= -32 {
            return Data([UInt8(bitPattern: Int8(value))])
        }

        if value >= 0 {
            if value <= 0xff {
                return Data([0xcc, UInt8(value)])
            }
            if value <= 0xffff {
                var v = UInt16(value).bigEndian
                return Data([0xcd]) + Data(bytes: &v, count: 2)
            }
            if value <= 0xffffffff {
                var v = UInt32(value).bigEndian
                return Data([0xce]) + Data(bytes: &v, count: 4)
            }
            var v = UInt64(value).bigEndian
            return Data([0xcf]) + Data(bytes: &v, count: 8)
        }

        var v = value.bigEndian
        return Data([0xd3]) + Data(bytes: &v, count: 8)
    }


    private static func encodeStringOrBinary(_ bytes: Data, isString: Bool) -> Data {

        let count = bytes.count

        if isString {

            if count <= 31 {
                return Data([0xa0 | UInt8(count)]) + bytes
            }
            if count <= 0xff {
                return Data([0xd9, UInt8(count)]) + bytes
            }
            if count <= 0xffff {
                var v = UInt16(count).bigEndian
                return Data([0xda]) + Data(bytes: &v, count: 2) + bytes
            }
            var v = UInt32(count).bigEndian
            return Data([0xdb]) + Data(bytes: &v, count: 4) + bytes

        } else {

            if count <= 0xff {
                return Data([0xc4, UInt8(count)]) + bytes
            }
            if count <= 0xffff {
                var v = UInt16(count).bigEndian
                return Data([0xc5]) + Data(bytes: &v, count: 2) + bytes
            }
            var v = UInt32(count).bigEndian
            return Data([0xc6]) + Data(bytes: &v, count: 4) + bytes
        }
    }


    private static func encodeArrayHeader(count: Int) -> Data {

        if count <= 15 {
            return Data([0x90 | UInt8(count)])
        }
        if count <= 0xffff {
            var v = UInt16(count).bigEndian
            return Data([0xdc]) + Data(bytes: &v, count: 2)
        }
        var v = UInt32(count).bigEndian
        return Data([0xdd]) + Data(bytes: &v, count: 4)
    }


    private static func encodeMapHeader(count: Int) -> Data {

        if count <= 15 {
            return Data([0x80 | UInt8(count)])
        }
        if count <= 0xffff {
            var v = UInt16(count).bigEndian
            return Data([0xde]) + Data(bytes: &v, count: 2)
        }
        var v = UInt32(count).bigEndian
        return Data([0xdf]) + Data(bytes: &v, count: 4)
    }
}
