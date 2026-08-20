import ControlKit
import Darwin
import Foundation
import XCTest

final class ControlServerTests: XCTestCase {
    private var servers: [ControlServer] = []

    override func tearDown() {
        for server in servers {
            server.stop()
        }
        servers.removeAll()
        super.tearDown()
    }

    func testRoundTripDeliversRequestAndResponse() throws {
        let path = makePath()
        startServer(path: path) { request, respond in
            XCTAssertEqual(request.action, .list)
            respond(ControlResponse(ok: true, dump: "pong"))
        }
        let response = try ControlClient.send(ControlRequest(action: .list), path: path, timeout: 5)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.dump, "pong")
    }

    func testHandlerMayRespondAsynchronouslyFromAnotherQueue() throws {
        let path = makePath()
        startServer(path: path) { _, respond in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                respond(ControlResponse(ok: true, dump: "late"))
            }
        }
        let response = try ControlClient.send(ControlRequest(action: .list), path: path, timeout: 5)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.dump, "late")
    }

    func testMalformedRequestGetsFailureResponse() throws {
        let path = makePath()
        startServer(path: path) { _, respond in
            respond(ControlResponse(ok: true))
        }
        let fd = try connectRaw(to: path)
        defer { close(fd) }
        try sendRaw(Data("this is not json\n".utf8), over: fd)
        let response = try readResponse(from: fd)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Invalid control request.")
    }

    func testRequestWithoutTrailingNewlineStillDecodesOnEOF() throws {
        let path = makePath()
        startServer(path: path) { request, respond in
            respond(ControlResponse(ok: true, dump: request.action.rawValue))
        }
        let fd = try connectRaw(to: path)
        defer { close(fd) }
        var payload = try ControlCodec.encode(ControlRequest(action: .list))
        payload.removeLast()
        try sendRaw(payload, over: fd)
        shutdown(fd, SHUT_WR)
        let response = try readResponse(from: fd)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.dump, "list")
    }

    func testOversizedRequestIsRejectedAndServerStaysUp() throws {
        let path = makePath()
        startServer(path: path, limits: .init(maxRequestBytes: 1024, readTimeout: 5)) { _, respond in
            respond(ControlResponse(ok: true, dump: "pong"))
        }
        let fd = try connectRaw(to: path)
        defer { close(fd) }
        try sendRaw(Data(repeating: 0x61, count: 4096), over: fd)
        let rejected = try readResponse(from: fd)
        XCTAssertFalse(rejected.ok)
        XCTAssertEqual(rejected.error, "Control request too large.")

        let followUp = try ControlClient.send(ControlRequest(action: .list), path: path, timeout: 5)
        XCTAssertTrue(followUp.ok)
        XCTAssertEqual(followUp.dump, "pong")
    }

    func testSilentClientCannotStallTheServer() throws {
        let path = makePath()
        startServer(path: path, limits: .init(readTimeout: 0.3)) { _, respond in
            respond(ControlResponse(ok: true, dump: "pong"))
        }
        let stalled = try connectRaw(to: path)
        defer { close(stalled) }

        let started = Date()
        let response = try ControlClient.send(ControlRequest(action: .list), path: path, timeout: 10)
        XCTAssertTrue(response.ok)
        XCTAssertLessThan(Date().timeIntervalSince(started), 8)

        let rejected = try readResponse(from: stalled)
        XCTAssertFalse(rejected.ok)
        XCTAssertEqual(rejected.error, "Control request timed out.")
    }

    func testDroppedResponderClosesTheConnection() throws {
        let path = makePath()
        startServer(path: path) { _, _ in
            // Discard `respond`; the client must see EOF, not a hang.
        }
        XCTAssertThrowsError(try ControlClient.send(ControlRequest(action: .list), path: path, timeout: 5))
    }

    func testClientTimesOutWhenServerNeverResponds() throws {
        let path = makePath()
        let held = HeldResponder()
        startServer(path: path) { _, respond in
            held.store(respond)
        }
        XCTAssertThrowsError(try ControlClient.send(ControlRequest(action: .list), path: path, timeout: 0.3)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ETIMEDOUT)
        }
        // Answer after the client is gone: the write hits a dead peer and
        // must not raise SIGPIPE (which would kill this test process).
        held.fire(ControlResponse(ok: true))
        Thread.sleep(forTimeInterval: 0.2)
    }

    // MARK: - Helpers

    private func makePath() -> String {
        "/tmp/candela-test-\(UUID().uuidString.prefix(8)).sock"
    }

    @discardableResult
    private func startServer(
        path: String,
        limits: ControlServer.Limits = ControlServer.Limits(),
        handler: @escaping (ControlRequest, @escaping (ControlResponse) -> Void) -> Void
    ) -> ControlServer {
        let server = ControlServer(path: path, limits: limits, handler: handler)
        server.start()
        servers.append(server)
        return server
    }

    private func connectRaw(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ECONNREFUSED) }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        precondition(bytes.count <= MemoryLayout.size(ofValue: addr.sun_path))
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            bytes.withUnsafeBytes { raw in
                buffer.copyMemory(from: raw)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, len)
            }
        }
        guard connected == 0 else {
            close(fd)
            throw POSIXError(.ECONNREFUSED)
        }
        return fd
    }

    private func sendRaw(_ data: Data, over fd: Int32) throws {
        let sent = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return write(fd, base, raw.count)
        }
        guard sent == data.count else { throw POSIXError(.EIO) }
    }

    private func readResponse(from fd: Int32) throws -> ControlResponse {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                let sawNewline = chunk[0..<count].contains(0x0A)
                buffer.append(contentsOf: chunk[0..<count])
                if sawNewline { break }
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw POSIXError(.ETIMEDOUT)
            }
        }
        return try ControlCodec.decode(ControlResponse.self, from: buffer)
    }
}

private final class HeldResponder {
    private let lock = NSLock()
    private var respond: ((ControlResponse) -> Void)?

    func store(_ respond: @escaping (ControlResponse) -> Void) {
        lock.lock()
        self.respond = respond
        lock.unlock()
    }

    func fire(_ response: ControlResponse) {
        lock.lock()
        let respond = self.respond
        self.respond = nil
        lock.unlock()
        respond?(response)
    }
}
