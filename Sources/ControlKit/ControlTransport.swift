import Darwin
import Foundation

public enum ControlCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let decoder = JSONDecoder()

    public static func encode(_ value: some Encodable) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var payload = data
        if payload.last == 0x0A {
            payload.removeLast()
        }
        return try decoder.decode(type, from: payload)
    }
}

public final class ControlServer {
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "candela.control.server")
    private let path: String
    private let handler: (ControlRequest) -> ControlResponse

    public init(path: String = ControlSocket.defaultPath, handler: @escaping (ControlRequest) -> ControlResponse) {
        self.path = path
        self.handler = handler
    }

    public func start() {
        queue.sync {
            stopLocked()
            let directory = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            unlink(path)

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = path.utf8CString
            guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
                close(fd)
                return
            }
            withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
                bytes.withUnsafeBytes { raw in
                    buffer.copyMemory(from: raw)
                }
            }
            let len = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, len)
                }
            }
            guard bound == 0, listen(fd, 8) == 0 else {
                close(fd)
                return
            }
            chmod(path, 0o600)
            listener = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptLocked()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            self.source = source
        }
    }

    public func stop() {
        queue.sync { stopLocked() }
    }

    deinit {
        stop()
    }

    private func stopLocked() {
        source?.cancel()
        source = nil
        if listener >= 0 {
            listener = -1
        }
        unlink(path)
    }

    private func acceptLocked() {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
            if buffer.contains(0x0A) { break }
        }
        let response: ControlResponse
        do {
            let request = try ControlCodec.decode(ControlRequest.self, from: buffer)
            response = handler(request)
        } catch {
            response = .failure("Invalid control request.")
        }
        if let payload = try? ControlCodec.encode(response) {
            payload.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                _ = write(client, base, raw.count)
            }
        }
    }
}

public enum ControlClient {
    public static func send(_ request: ControlRequest, path: String = ControlSocket.defaultPath) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ECONNREFUSED) }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            bytes.withUnsafeBytes { raw in
                buffer.copyMemory(from: raw)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, len)
            }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
        let payload = try ControlCodec.encode(request)
        let written = payload.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return write(fd, base, raw.count)
        }
        guard written == payload.count else { throw POSIXError(.EIO) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
            if buffer.contains(0x0A) { break }
        }
        return try ControlCodec.decode(ControlResponse.self, from: buffer)
    }
}
