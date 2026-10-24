import Compression
import Foundation

/// zlib's deflate, as Apple's Compression has it: how the key-value store
/// kept each space, read back once (Sync.legacySpaces).
enum Deflate {
    /// The same form, the other way: its length first, then zlib's deflate.
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count < 8_000_000 else { return nil }
        var buffer = [UInt8](repeating: 0, count: data.count + 1024)
        let written = data.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(&buffer, buffer.count, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        var length = UInt32(data.count).littleEndian
        return Data(bytes: &length, count: 4) + Data(buffer.prefix(written))
    }

    static func inflate(_ data: Data) -> Data? {
        guard data.count > 4 else { return nil }
        let size = data.prefix(4).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard size > 0, size < 8_000_000 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let body = data.dropFirst(4)
        let read = body.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&buffer, size, base, body.count, nil, COMPRESSION_ZLIB)
        }
        return read == size ? Data(buffer) : nil
    }
}
