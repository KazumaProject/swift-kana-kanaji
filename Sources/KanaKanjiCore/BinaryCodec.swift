import Foundation

struct BinaryWriter {
    private(set) var data = Data()

    mutating func writeBytes(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    mutating func writeUInt64(_ value: UInt64) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt32(_ value: UInt32) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt16(_ value: UInt16) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func writeInt64(_ value: Int64) {
        writeUInt64(UInt64(bitPattern: value))
    }

    mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    mutating func writeInt16(_ value: Int16) {
        writeUInt16(UInt16(bitPattern: value))
    }

    mutating func writeString(_ value: String) {
        let bytes = Array(value.utf8)
        writeUInt64(UInt64(bytes.count))
        writeBytes(bytes)
    }
}

struct BinaryReader {
    let data: Data
    var offset = 0

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else {
            throw BinaryReaderError.unexpectedEndOfFile
        }

        let bytes = Array(data[offset..<(offset + count)])
        offset += count
        return bytes
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readBytes(count: 8)
        var value: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt64(byte) << UInt64(index * 8)
        }
        return value
    }

    mutating func readUInt32LE() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        var value: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt32(byte) << UInt32(index * 8)
        }
        return value
    }

    mutating func readUInt16LE() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    mutating func readInt32LE() throws -> Int32 {
        Int32(bitPattern: try readUInt32LE())
    }

    mutating func readInt16LE() throws -> Int16 {
        Int16(bitPattern: try readUInt16LE())
    }

    mutating func readUInt64LE() throws -> UInt64 {
        try readUInt64()
    }

    mutating func readInt64LE() throws -> Int64 {
        try readInt64()
    }

    mutating func readString() throws -> String {
        let count = try readIntCount()
        let bytes = try readBytes(count: count)
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw BinaryReaderError.invalidUTF8
        }
        return string
    }

    mutating func readIntCount() throws -> Int {
        let value = try readUInt64()
        guard value <= UInt64(Int.max) else {
            throw BinaryReaderError.countOutOfRange
        }
        return Int(value)
    }

    var isAtEnd: Bool {
        offset == data.count
    }
}

enum BinaryReaderError: Error {
    case unexpectedEndOfFile
    case invalidUTF8
    case countOutOfRange
}
