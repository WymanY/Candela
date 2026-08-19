import ControlKit
import Foundation

@main
enum CandelaMCP {
    static func main() {
        let transport = MCPStdioTransport()
        transport.run()
    }
}

final class MCPStdioTransport {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func run() {
        encoder.outputFormatting = []
        let stdin = FileHandle.standardInput
        while true {
            guard let line = readLine(from: stdin) else { break }
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            handle(line: line)
        }
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            let request = try decoder.decode(JSONRPCRequest.self, from: data)
            let response = dispatch(request)
            write(response)
        } catch {
            write(JSONRPCResponse(jsonrpc: "2.0", id: nil, result: nil, error: JSONRPCError(code: -32700, message: "Parse error")))
        }
    }

    private func dispatch(_ request: JSONRPCRequest) -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object([
                    "protocolVersion": .string("2024-11-05"),
                    "capabilities": .object(["tools": .object([:])]),
                    "serverInfo": .object([
                        "name": .string("candela"),
                        "version": .string("1.0.0"),
                    ]),
                ]),
                error: nil
            )
        case "notifications/initialized", "initialized":
            return JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: .object([:]), error: nil)
        case "tools/list":
            return JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: .object(["tools": .array(Self.tools)]), error: nil)
        case "tools/call":
            return callTool(request)
        case "ping":
            return JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: .object([:]), error: nil)
        default:
            return JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: nil, error: JSONRPCError(code: -32601, message: "Method not found"))
        }
    }

    private func callTool(_ request: JSONRPCRequest) -> JSONRPCResponse {
        guard case let .object(params)? = request.params,
              case let .string(name)? = params["name"]
        else {
            return JSONRPCResponse(jsonrpc: "2.0", id: request.id, result: nil, error: JSONRPCError(code: -32602, message: "Missing tool name"))
        }
        let arguments = params["arguments"] ?? .object([:])
        do {
            let control = try Self.request(for: name, arguments: arguments)
            let response = try ControlClient.send(control)
            let payload = try ControlCodec.encoder.encode(response)
            let text = String(data: payload, encoding: .utf8) ?? "{}"
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "isError": .bool(!response.ok),
                ]),
                error: nil
            )
        } catch {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(error.localizedDescription)])]),
                    "isError": .bool(true),
                ]),
                error: nil
            )
        }
    }

    private static func request(for name: String, arguments: JSONValue) throws -> ControlRequest {
        let object = arguments.objectValue
        switch name {
        case "candela_list_displays":
            return ControlRequest(action: .list)
        case "candela_get_display":
            return ControlRequest(action: .get, display: try required(object, "display"))
        case "candela_set_brightness":
            return ControlRequest(action: .setBrightness, display: try required(object, "display"), value: try requiredDouble(object, "value"))
        case "candela_set_volume":
            return ControlRequest(action: .setVolume, display: try required(object, "display"), value: try requiredDouble(object, "value"))
        case "candela_set_mute":
            return ControlRequest(action: .setMuted, display: try required(object, "display"), muted: try requiredBool(object, "muted"))
        case "candela_set_contrast":
            return ControlRequest(action: .setContrast, display: try required(object, "display"), value: try requiredDouble(object, "value"))
        case "candela_set_input":
            return ControlRequest(action: .setInput, display: try required(object, "display"), input: try required(object, "input"))
        case "candela_set_rotation":
            return ControlRequest(action: .setRotation, display: try required(object, "display"), rotation: try required(object, "rotation"))
        case "candela_set_picture_in_picture":
            if object["mode"] != nil || object["window"] != nil || object["bundle"] != nil || object["zoom"] != nil || object["mirrored"] != nil {
                return ControlRequest(
                    action: .configurePictureInPicture,
                    display: try required(object, "display"),
                    pictureInPicture: object["enabled"]?.boolValue ?? true,
                    pictureInPictureMode: object["mode"]?.stringValue,
                    pictureInPictureMirrored: object["mirrored"]?.boolValue,
                    pictureInPictureWindow: object["window"]?.stringValue,
                    pictureInPictureBundle: object["bundle"]?.stringValue,
                    pictureInPictureZoom: object["zoom"]?.doubleValue
                )
            }
            return ControlRequest(action: .setPictureInPicture, display: try required(object, "display"), pictureInPicture: try requiredBool(object, "enabled"))
        case "candela_set_picture_in_picture_wall":
            return ControlRequest(action: .setPictureInPictureWall, pictureInPicture: try requiredBool(object, "enabled"))
        case "candela_rename_display":
            return ControlRequest(action: .rename, display: try required(object, "display"), name: object["name"]?.stringValue)
        case "candela_apply_preset":
            return ControlRequest(action: .preset, display: object["display"]?.stringValue, preset: try required(object, "preset"))
        case "candela_match_all":
            return ControlRequest(action: .matchAll, display: try required(object, "display"))
        case "candela_set_builtin_mirror":
            return ControlRequest(action: .setBuiltInMirror)
        case "candela_list_scenes":
            return ControlRequest(action: .listScenes)
        case "candela_apply_scene":
            return ControlRequest(action: .applyScene, scene: try required(object, "scene"))
        case "candela_save_scene":
            return ControlRequest(action: .saveScene, name: try required(object, "name"))
        case "candela_rename_scene":
            return ControlRequest(action: .renameScene, name: try required(object, "name"), scene: try required(object, "scene"))
        case "candela_delete_scene":
            return ControlRequest(action: .deleteScene, scene: try required(object, "scene"))
        case "candela_debug_dump":
            return ControlRequest(action: .dump, redact: object["redact"]?.boolValue ?? true)
        default:
            throw MCPError.unknownTool(name)
        }
    }

    private static func required(_ object: [String: JSONValue], _ key: String) throws -> String {
        guard let value = object[key]?.stringValue, !value.isEmpty else {
            throw MCPError.missing(key)
        }
        return value
    }

    private static func requiredDouble(_ object: [String: JSONValue], _ key: String) throws -> Double {
        if let value = object[key]?.doubleValue { return value }
        if let raw = object[key]?.stringValue, let value = Double(raw) { return value }
        throw MCPError.missing(key)
    }

    private static func requiredBool(_ object: [String: JSONValue], _ key: String) throws -> Bool {
        if let value = object[key]?.boolValue { return value }
        throw MCPError.missing(key)
    }

    private static let tools: [JSONValue] = [
        tool("candela_list_displays", "List connected displays and their current brightness, volume, contrast, and input."),
        tool("candela_get_display", "Get one display by name, persistentKey, main, builtin, or external.", [
            "display": schema("string", "Display query"),
        ], ["display"]),
        tool("candela_set_brightness", "Set display brightness in the 0...1 range.", [
            "display": schema("string", "Display query"),
            "value": schema("number", "Brightness from 0 to 1"),
        ], ["display", "value"]),
        tool("candela_set_volume", "Set HDMI/DP speaker volume in the 0...1 range.", [
            "display": schema("string", "Display query"),
            "value": schema("number", "Volume from 0 to 1"),
        ], ["display", "value"]),
        tool("candela_set_mute", "Mute or unmute a display's speakers.", [
            "display": schema("string", "Display query"),
            "muted": schema("boolean", "true to mute"),
        ], ["display", "muted"]),
        tool("candela_set_contrast", "Set DDC contrast in the 0...1 range when the monitor supports VCP 0x12.", [
            "display": schema("string", "Display query"),
            "value": schema("number", "Contrast from 0 to 1"),
        ], ["display", "value"]),
        tool("candela_set_input", "Switch DDC input (hdmi1, hdmi2, dp, dp2, usbc, or a VCP 0x60 code).", [
            "display": schema("string", "Display query"),
            "input": schema("string", "Input name or code"),
        ], ["display", "input"]),
        tool("candela_set_rotation", "Rotate an external display to 0, 90, 180, or 270 degrees. Built-in panels are not supported.", [
            "display": schema("string", "Display query"),
            "rotation": schema("string", "0, 90, 180, 270, landscape, or portrait"),
        ], ["display", "rotation"]),
        tool("candela_set_picture_in_picture", "Open, close, or configure a floating Picture in Picture window for a display.", [
            "display": schema("string", "Display query"),
            "enabled": schema("boolean", "true to open, false to close"),
            "mode": schema("string", "display, window, or magnifier"),
            "mirrored": schema("boolean", "Flip the preview horizontally"),
            "window": schema("string", "Window title or app name"),
            "bundle": schema("string", "Bundle identifier for window follow"),
            "zoom": schema("number", "Magnifier zoom from 1.5 to 4"),
        ], ["display"]),
        tool("candela_set_picture_in_picture_wall", "Open or close the multi-display monitor wall.", [
            "enabled": schema("boolean", "true to open, false to close"),
        ], ["enabled"]),
        tool("candela_rename_display", "Set or clear a custom display name.", [
            "display": schema("string", "Display query"),
            "name": schema("string", "Custom name; omit or empty to reset"),
        ], ["display"]),
        tool("candela_apply_preset", "Apply night (20%), desk (50%), or max (100%) brightness.", [
            "display": schema("string", "Display query or all"),
            "preset": schema("string", "night, desk, or max"),
        ], ["preset"]),
        tool("candela_match_all", "Copy this display's brightness, volume, and contrast onto the others.", [
            "display": schema("string", "Source display query"),
        ], ["display"]),
        tool("candela_set_builtin_mirror", "Mirror every attached display onto the built-in panel, or restore the previous arrangement."),
        tool("candela_list_scenes", "List saved display scenes."),
        tool("candela_apply_scene", "Apply a saved scene by name or id.", [
            "scene": schema("string", "Scene name or id"),
        ], ["scene"]),
        tool("candela_save_scene", "Save the current display state as a named scene. Reuses a scene with the same name.", [
            "name": schema("string", "Scene name"),
        ], ["name"]),
        tool("candela_rename_scene", "Rename a saved scene.", [
            "scene": schema("string", "Existing scene name or id"),
            "name": schema("string", "New scene name"),
        ], ["scene", "name"]),
        tool("candela_delete_scene", "Delete a saved scene.", [
            "scene": schema("string", "Scene name or id"),
        ], ["scene"]),
        tool("candela_debug_dump", "Copy a redacted debug dump of the live catalog.", [
            "redact": schema("boolean", "Redact serials"),
        ], []),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: JSONValue] = [:], _ required: [String] = []) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
            ]),
        ])
    }

    private static func schema(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    private func write(_ response: JSONRPCResponse) {
        guard let data = try? encoder.encode(response), var text = String(data: data, encoding: .utf8) else { return }
        text.append("\n")
        FileHandle.standardOutput.write(Data(text.utf8))
        fflush(stdout)
    }

    private func readLine(from handle: FileHandle) -> String? {
        var buffer = Data()
        while true {
            let chunk = handle.readData(ofLength: 1)
            if chunk.isEmpty {
                return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
            }
            if chunk == Data([0x0A]) {
                return String(data: buffer, encoding: .utf8)
            }
            buffer.append(chunk)
        }
    }
}

enum MCPError: LocalizedError {
    case unknownTool(String)
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "Unknown tool \(name)"
        case .missing(let key): return "Missing argument \(key)"
        }
    }
}

struct JSONRPCRequest: Decodable {
    var jsonrpc: String?
    var id: JSONValue?
    var method: String
    var params: JSONValue?
}

struct JSONRPCResponse: Encodable {
    var jsonrpc: String
    var id: JSONValue?
    var result: JSONValue?
    var error: JSONRPCError?
}

struct JSONRPCError: Encodable {
    var code: Int
    var message: String
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var objectValue: [String: JSONValue] {
        if case let .object(value) = self { return value }
        return [:]
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
