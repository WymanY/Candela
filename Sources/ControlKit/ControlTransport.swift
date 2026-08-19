import Darwin
import Foundation

public enum ControlCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encode(_ value: some Encodable) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var payload = firstLine(of: data)
        if payload.last == 0x0A {
            payload.removeLast()
        }
        return try decoder.decode(type, from: payload)
    }

    /// One message per line; anything a peer sends after the first newline is ignored.
    static func firstLine(of data: Data) -> Data {
        guard let index = data.firstIndex(of: 0x0A) else { return data }
        return Data(data.prefix(through: index))
    }
}

public final class ControlServer {
    public struct Limits: Sendable {
        public var maxRequestBytes: Int
        public var readTimeout: TimeInterval
        public var writeTimeout: TimeInterval

        public init(
            maxRequestBytes: Int = 64 * 1024,
            readTimeout: TimeInterval = 2.0,
            writeTimeout: TimeInterval = 2.0
        ) {
            self.maxRequestBytes = maxRequestBytes
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout
        }
    }

    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "candela.control.server")
    private let path: String
    private let limits: Limits
    private let handler: (ControlRequest, @escaping (ControlResponse) -> Void) -> Void

    /// `handler` is called on the server queue and may complete `respond`
    /// once, from any queue, immediately or later. Dropping `respond`
    /// without calling it closes the connection.
    public init(
        path: String = ControlSocket.defaultPath,
        limits: Limits = Limits(),
        handler: @escaping (ControlRequest, @escaping (ControlResponse) -> Void) -> Void
    ) {
        self.path = path
        self.limits = limits
        self.handler = handler
    }

    public func start() {
        queue.sync {
            stopLocked()
            let directory = (path as NSString).deletingLastPathComponent
            if !FileManager.default.fileExists(atPath: directory) {
                // Only set permissions on directories we create; the parent may
                // be a shared location like /tmp in tests.
                try? FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
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
            guard bound == 0 else {
                close(fd)
                return
            }
            // Tighten the socket file before listen() opens the door;
            // bind() creates it with umask-derived permissions.
            chmod(path, 0o600)
            guard listen(fd, 8) == 0 else {
                close(fd)
                unlink(path)
                return
            }
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
        guard Self.peerIsCurrentUser(client) else {
            close(client)
            return
        }
        // Wake blocking reads at least every 250 ms so the overall deadline
        // below holds even against a peer that trickles bytes forever.
        Self.configure(
            socket: client,
            receiveTimeout: max(0.05, min(0.25, limits.readTimeout / 2)),
            sendTimeout: max(0.05, limits.writeTimeout)
        )
        var buffer = Data()
        switch Self.readRequest(into: &buffer, from: client, limits: limits) {
        case .complete:
            break
        case .disconnected:
            // Peers may send the payload and shut down their write side
            // without a trailing newline; decode whatever arrived.
            guard !buffer.isEmpty else {
                close(client)
                return
            }
        case .timedOut:
            Self.respondAndClose(client, .failure("Control request timed out."))
            return
        case .tooLarge:
            Self.respondAndClose(client, .failure("Control request too large."))
            return
        }
        guard let request = try? ControlCodec.decode(ControlRequest.self, from: buffer) else {
            Self.respondAndClose(client, .failure("Invalid control request."))
            return
        }
        let responder = ConnectionResponder(fd: client, queue: queue)
        handler(request) { response in
            responder.respond(response)
        }
    }

    private enum ReadOutcome {
        case complete
        case disconnected
        case timedOut
        case tooLarge
    }

    private static func readRequest(into buffer: inout Data, from fd: Int32, limits: Limits) -> ReadOutcome {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let deadline = Date(timeIntervalSinceNow: limits.readTimeout)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                let sawNewline = chunk[0..<count].contains(0x0A)
                buffer.append(contentsOf: chunk[0..<count])
                if sawNewline { return .complete }
                if buffer.count > limits.maxRequestBytes { return .tooLarge }
            } else if count == 0 {
                return .disconnected
            } else if errno == EINTR {
                continue
            } else if errno != EAGAIN && errno != EWOULDBLOCK {
                return .disconnected
            }
            if Date() >= deadline { return .timedOut }
        }
    }

    private static func peerIsCurrentUser(_ fd: Int32) -> Bool {
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(fd, &uid, &gid) == 0 else { return false }
        return uid == getuid()
    }

    private static func configure(socket fd: Int32, receiveTimeout: TimeInterval, sendTimeout: TimeInterval) {
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var receive = timeval(interval: receiveTimeout)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receive, socklen_t(MemoryLayout<timeval>.size))
        var send = timeval(interval: sendTimeout)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &send, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func respondAndClose(_ fd: Int32, _ response: ControlResponse) {
        send(response, over: fd)
        close(fd)
    }

    fileprivate static func send(_ response: ControlResponse, over fd: Int32) {
        guard let payload = try? ControlCodec.encode(response) else { return }
        // A peer that vanished mid-write yields EPIPE here; SO_NOSIGPIPE
        // keeps that from raising SIGPIPE and killing the process.
        _ = writeAll(payload, to: fd)
    }

    /// Owns an accepted connection until exactly one response is written.
    /// Dropping the responder without answering closes the socket so the
    /// client sees EOF instead of a hang.
    private final class ConnectionResponder {
        private let lock = NSLock()
        private var fd: Int32?
        private let queue: DispatchQueue

        init(fd: Int32, queue: DispatchQueue) {
            self.fd = fd
            self.queue = queue
        }

        func respond(_ response: ControlResponse) {
            guard let fd = take() else { return }
            queue.async {
                ControlServer.send(response, over: fd)
                close(fd)
            }
        }

        private func take() -> Int32? {
            lock.lock()
            defer { lock.unlock() }
            let fd = self.fd
            self.fd = nil
            return fd
        }

        deinit {
            if let fd = take() {
                close(fd)
            }
        }
    }
}

public enum ControlClient {
    public static let maxResponseBytes = 8 * 1024 * 1024

    public static func send(
        _ request: ControlRequest,
        path: String = ControlSocket.defaultPath,
        timeout: TimeInterval = 5
    ) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ECONNREFUSED) }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var interval = timeval(interval: timeout)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
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
        guard writeAll(payload, to: fd) else { throw POSIXError(.EIO) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                let sawNewline = chunk[0..<count].contains(0x0A)
                buffer.append(contentsOf: chunk[0..<count])
                if sawNewline { break }
                guard buffer.count <= maxResponseBytes else { throw POSIXError(.EMSGSIZE) }
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                throw POSIXError(.ETIMEDOUT)
            } else {
                throw POSIXError(.EIO)
            }
        }
        return try ControlCodec.decode(ControlResponse.self, from: buffer)
    }
}

private func writeAll(_ data: Data, to fd: Int32) -> Bool {
    data.withUnsafeBytes { raw -> Bool in
        guard var base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
        var remaining = raw.count
        while remaining > 0 {
            let written = write(fd, base, remaining)
            if written > 0 {
                base += written
                remaining -= written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }
}

private extension timeval {
    init(interval: TimeInterval) {
        let clamped = max(0.001, interval)
        let seconds = Int(clamped)
        self.init(tv_sec: seconds, tv_usec: suseconds_t((clamped - Double(seconds)) * 1_000_000))
    }
}
