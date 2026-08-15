import ControlKit
import Darwin
import Foundation

@main
enum CandelaCLI {
    static func main() {
        do {
            let request = try parse(Array(CommandLine.arguments.dropFirst()))
            let response = try ControlClient.send(request)
            printJSON(response)
            if !response.ok {
                exit(1)
            }
        } catch {
            let failed = ControlResponse.failure(error.localizedDescription)
            printJSON(failed)
            exit(1)
        }
    }

    static func parse(_ args: [String]) throws -> ControlRequest {
        guard let command = args.first else {
            throw CLIError.usage
        }
        let rest = Array(args.dropFirst())
        switch command {
        case "list":
            return ControlRequest(action: .list)
        case "get":
            return ControlRequest(action: .get, display: try requiredDisplay(rest))
        case "set-brightness":
            return ControlRequest(action: .setBrightness, display: try requiredDisplay(rest), value: try requiredValue(rest))
        case "set-volume":
            return ControlRequest(action: .setVolume, display: try requiredDisplay(rest), value: try requiredValue(rest))
        case "set-mute":
            return ControlRequest(action: .setMuted, display: try requiredDisplay(rest), muted: try requiredBool(rest))
        case "set-contrast":
            return ControlRequest(action: .setContrast, display: try requiredDisplay(rest), value: try requiredValue(rest))
        case "set-input":
            return ControlRequest(action: .setInput, display: try requiredDisplay(rest), input: try requiredToken(rest, name: "input"))
        case "set-rotation":
            return ControlRequest(action: .setRotation, display: try requiredDisplay(rest), rotation: try requiredToken(rest, name: "rotation"))
        case "set-pip":
            return ControlRequest(action: .setPictureInPicture, display: try requiredDisplay(rest), pictureInPicture: try requiredBool(rest, names: ["--enabled", "--value", "--pip"]))
        case "rename":
            return ControlRequest(action: .rename, display: try requiredDisplay(rest), name: optionalName(rest))
        case "preset":
            return ControlRequest(action: .preset, display: optionalDisplay(rest), preset: try requiredToken(rest, name: "preset"))
        case "match-all":
            return ControlRequest(action: .matchAll, display: try requiredDisplay(rest))
        case "scenes":
            return ControlRequest(action: .listScenes)
        case "apply-scene":
            return ControlRequest(action: .applyScene, scene: try requiredToken(rest, name: "scene"))
        case "save-scene":
            return ControlRequest(action: .saveScene, name: try requiredName(rest))
        case "rename-scene":
            return ControlRequest(action: .renameScene, name: try requiredName(rest), scene: try requiredToken(rest, name: "scene"))
        case "delete-scene":
            return ControlRequest(action: .deleteScene, scene: try requiredToken(rest, name: "scene"))
        case "dump":
            return ControlRequest(action: .dump, redact: !rest.contains("--no-redact"))
        case "help", "-h", "--help":
            throw CLIError.usage
        default:
            throw CLIError.unknown(command)
        }
    }

    static func requiredDisplay(_ args: [String]) throws -> String {
        if let value = named(args, names: ["--display", "-d"]) { return value }
        if let first = args.first, !first.hasPrefix("-") { return first }
        throw CLIError.usage
    }

    static func optionalDisplay(_ args: [String]) -> String? {
        if let value = named(args, names: ["--display", "-d"]) { return value }
        if let first = args.first, !first.hasPrefix("-"), first.lowercased() != "night", first.lowercased() != "desk", first.lowercased() != "max" {
            return first
        }
        return nil
    }

    static func requiredValue(_ args: [String]) throws -> Double {
        if let raw = named(args, names: ["--value", "-v"]) ?? args.dropFirst().first(where: { !$0.hasPrefix("-") && Double($0) != nil }) {
            guard let value = Double(raw) else { throw CLIError.usage }
            return value
        }
        throw CLIError.usage
    }

    static func requiredBool(_ args: [String], names: [String] = ["--muted", "--value"]) throws -> Bool {
        if let raw = named(args, names: names) ?? args.dropFirst().first(where: { ["true", "false", "1", "0", "on", "off"].contains($0.lowercased()) }) {
            switch raw.lowercased() {
            case "true", "1", "on": return true
            case "false", "0", "off": return false
            default: break
            }
        }
        throw CLIError.usage
    }

    static func requiredToken(_ args: [String], name: String) throws -> String {
        if let value = named(args, names: ["--\(name)"]) { return value }
        if name == "preset", let last = args.last, ["night", "desk", "max"].contains(last.lowercased()) {
            return last.lowercased()
        }
        if ["input", "rotation", "scene"].contains(name), let first = positional(args).first {
            return first
        }
        throw CLIError.usage
    }

    static func requiredName(_ args: [String]) throws -> String {
        if let value = named(args, names: ["--name"]) { return value }
        let values = positional(args)
        if values.count >= 2 { return values[1] }
        if values.count == 1 { return values[0] }
        throw CLIError.usage
    }

    static func optionalName(_ args: [String]) -> String? {
        named(args, names: ["--name"]) ?? args.dropFirst().first(where: { !$0.hasPrefix("-") })
    }

    static func positional(_ args: [String]) -> [String] {
        var values: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--"), arg.contains("=") {
                index += 1
                continue
            }
            if arg.hasPrefix("-") {
                index += 2
                continue
            }
            values.append(arg)
            index += 1
        }
        return values
    }

    static func named(_ args: [String], names: [String]) -> String? {
        for (index, arg) in args.enumerated() {
            if names.contains(arg), index + 1 < args.count {
                return args[index + 1]
            }
            for name in names where arg.hasPrefix(name + "=") {
                return String(arg.dropFirst(name.count + 1))
            }
        }
        return nil
    }

    static func printJSON(_ response: ControlResponse) {
        if let data = try? ControlCodec.encode(response), let text = String(data: data, encoding: .utf8) {
            fputs(text, stdout)
        }
    }
}

enum CLIError: LocalizedError {
    case usage
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
            candela-cli <command> [options]
            commands: list get set-brightness set-volume set-mute set-contrast set-input set-rotation set-pip rename preset match-all scenes apply-scene save-scene rename-scene delete-scene dump
            display queries: name, persistentKey, main, builtin, external
            """
        case .unknown(let command):
            return "Unknown command '\(command)'."
        }
    }
}
