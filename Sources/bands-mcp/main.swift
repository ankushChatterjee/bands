import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A dependency-free MCP stdio server. The menu-bar app owns the data store;
/// this process forwards tool calls to its local Unix-domain socket.
final class UnixSocketProxy {
    private let path: String

    init(path: String = ProcessInfo.processInfo.environment["BANDS_MCP_SOCKET"] ??
         "\(NSHomeDirectory())/Library/Application Support/bands/mcp.sock") {
        self.path = path
    }

    func request(_ object: [String: Any]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProxyError.system(errno) }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else { throw ProxyError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            raw.copyBytes(from: pathBytes)
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
        }
        guard connected == 0 else { throw ProxyError.system(errno) }

        var payload = try JSONSerialization.data(withJSONObject: object)
        payload.append(0x0A)
        try payload.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { throw ProxyError.system(errno) }
                offset += written
            }
        }

        var response = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            guard count > 0 else {
                if count == 0 { throw ProxyError.closed }
                throw ProxyError.system(errno)
            }
            if byte == 0x0A { break }
            response.append(byte)
            if response.count > 8 * 1024 * 1024 { throw ProxyError.responseTooLarge }
        }
        guard let value = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw ProxyError.invalidResponse
        }
        return value
    }
}

enum ProxyError: Error {
    case system(Int32), pathTooLong, closed, responseTooLarge, invalidResponse
}

struct MCPServer {
    let proxy: UnixSocketProxy
    let tools: [[String: Any]] = [
        ["name": "list_bands", "description": "List bands in Bands.", "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "list_thoughts", "description": "List thoughts, optionally filtered by band or state.", "inputSchema": ["type": "object", "properties": ["bandId": ["type": "string"], "includeCompleted": ["type": "boolean"], "includeReleased": ["type": "boolean"]]]],
        ["name": "list_prioritized_thoughts", "description": "List active thoughts sorted by age-derived priority: fresh is low, warm is medium, attention is high, and old is urgent.", "inputSchema": ["type": "object", "properties": ["minimumPriority": ["type": "string", "enum": ["low", "medium", "high", "urgent"]]]]],
        ["name": "search", "description": "Search thoughts by text.", "inputSchema": ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"]]],
        ["name": "get", "description": "Get one thought by ID.", "inputSchema": ["type": "object", "properties": ["thoughtId": ["type": "string"]], "required": ["thoughtId"]]],
        ["name": "capture", "description": "Capture a new thought into Bands.", "inputSchema": ["type": "object", "properties": ["text": ["type": "string"], "bandId": ["type": "string"]], "required": ["text"]]],
        ["name": "update_thought", "description": "Edit an existing thought.", "inputSchema": ["type": "object", "properties": ["thoughtId": ["type": "string"], "text": ["type": "string"]], "required": ["thoughtId", "text"]]],
        ["name": "complete_thought", "description": "Mark a thought complete.", "inputSchema": ["type": "object", "properties": ["thoughtId": ["type": "string"]], "required": ["thoughtId"]]],
        ["name": "release_thought", "description": "Let a thought go.", "inputSchema": ["type": "object", "properties": ["thoughtId": ["type": "string"]], "required": ["thoughtId"]]],
        ["name": "move_thought", "description": "Move a thought to another band.", "inputSchema": ["type": "object", "properties": ["thoughtId": ["type": "string"], "bandId": ["type": "string"]], "required": ["thoughtId", "bandId"]]]
    ]

    func handle(_ request: [String: Any]) -> [String: Any]? {
        guard let method = request["method"] as? String else { return nil }
        let id = request["id"]
        if method.hasPrefix("notifications/") { return nil }
        if method == "initialize" {
            let requestedVersion = (request["params"] as? [String: Any])?["protocolVersion"] as? String
            let supportedVersions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
            let protocolVersion = requestedVersion.flatMap { supportedVersions.contains($0) ? $0 : nil } ?? "2025-11-25"
            return result(id, [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "bands", "version": "0.1.1"],
                "instructions": "Bands stores local thoughts. Use list_bands or list_thoughts before modifying a thought, and ask before creating, editing, moving, completing, or releasing one."
            ])
        }
        if method == "ping" { return result(id, [:]) }
        if method == "tools/list" { return result(id, ["tools": tools]) }
        if method == "tools/call" {
            guard let params = request["params"] as? [String: Any], let name = params["name"] as? String,
                  tools.contains(where: { $0["name"] as? String == name }) else {
                return error(id, -32602, "Unknown tool")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let backend = try proxy.request(["jsonrpc": "2.0", "id": id ?? NSNull(), "method": "bands.command", "params": ["name": name, "arguments": arguments]])
                if let backendError = backend["error"] { return ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": backendError] }
                guard let backendResult = backend["result"] else {
                    return error(id, -32002, "Bands returned an invalid MCP response")
                }
                return result(id, backendResult)
            } catch _ {
                return error(id, -32001, "Bands app is unavailable at the local MCP socket")
            }
        }
        return error(id, -32601, "Method not found")
    }

    private func result(_ id: Any?, _ value: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": value] }
    private func error(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]] }
    private func stringify(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
        return text
    }
}

let server = MCPServer(proxy: UnixSocketProxy())
while let line = readLine(strippingNewline: true) {
    guard let data = line.data(using: .utf8), let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    if let response = server.handle(request), let data = try? JSONSerialization.data(withJSONObject: response) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
