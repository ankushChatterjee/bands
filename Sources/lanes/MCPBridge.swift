import Foundation
import SwiftData
import Darwin

/// The app-owned command surface used by the local MCP helper.
@MainActor
final class LanesCommandService {
    private let container: ModelContainer

    init(container: ModelContainer) { self.container = container }

    func call(name: String, arguments: [String: Any]) -> [String: Any] {
        let context = ModelContext(container)
        do {
            switch name {
            case "lanes/list": return try list(context: context, arguments: arguments)
            case "lanes/prioritized": return try prioritized(context: context, arguments: arguments)
            case "lanes/search": return try search(context: context, arguments: arguments)
            case "lanes/get": return try get(context: context, arguments: arguments)
            case "lanes/capture": return try capture(context: context, arguments: arguments)
            case "lanes/edit": return try edit(context: context, arguments: arguments)
            case "lanes/move": return try move(context: context, arguments: arguments)
            case "lanes/complete": return try mark(context: context, arguments: arguments, release: false)
            case "lanes/release": return try mark(context: context, arguments: arguments, release: true)
            default: throw BridgeError(message: "Unknown tool: \(name)")
            }
        } catch let error as BridgeError { return ["error": error.message] }
        catch { return ["error": error.localizedDescription] }
    }

    private func lanes(_ context: ModelContext) throws -> [Lane] { try context.fetch(FetchDescriptor<Lane>()).sorted { $0.order < $1.order } }
    private func thoughts(_ context: ModelContext) throws -> [Thought] { try context.fetch(FetchDescriptor<Thought>()).sorted { ($0.order ?? 0) > ($1.order ?? 0) } }
    private func id(_ arguments: [String: Any]) throws -> UUID {
        guard let value = arguments["id"] as? String, let result = UUID(uuidString: value) else { throw BridgeError(message: "A valid id is required") }
        return result
    }
    private func lane(_ context: ModelContext, id: UUID) throws -> Lane {
        guard let lane = try lanes(context).first(where: { $0.id == id }) else { throw BridgeError(message: "Lane not found") }
        return lane
    }
    private func thought(_ context: ModelContext, id: UUID) throws -> Thought {
        guard let thought = try thoughts(context).first(where: { $0.id == id }) else { throw BridgeError(message: "Thought not found") }
        return thought
    }
    private func laneJSON(_ lane: Lane) -> [String: Any] { ["id": lane.id.uuidString, "name": lane.name, "order": lane.order, "createdAt": ISO8601DateFormatter().string(from: lane.createdAt)] }
    private func thoughtJSON(_ thought: Thought) -> [String: Any] {
        let age = ThoughtAging.age(for: thought)
        let ageMinutes = max(0, Int(Date.now.timeIntervalSince(thought.createdAt) / 60))
        var value: [String: Any] = ["id": thought.id.uuidString, "text": thought.text, "createdAt": ISO8601DateFormatter().string(from: thought.createdAt), "updatedAt": ISO8601DateFormatter().string(from: thought.updatedAt), "lastTouchedAt": ISO8601DateFormatter().string(from: thought.lastTouchedAt), "age": age.name, "ageMinutes": ageMinutes, "priority": age.priority.rawValue, "priorityRank": age.priority.rank]
        value["laneId"] = thought.lane?.id.uuidString as Any
        value["completedAt"] = thought.completedAt.map { ISO8601DateFormatter().string(from: $0) } as Any
        value["releasedAt"] = thought.releasedAt.map { ISO8601DateFormatter().string(from: $0) } as Any
        return value
    }
    private func list(context: ModelContext, arguments: [String: Any]) throws -> [String: Any] {
        let allLanes = try lanes(context); let laneID = (arguments["laneId"] as? String).flatMap(UUID.init(uuidString:))
        let includeCompleted = arguments["includeCompleted"] as? Bool ?? false; let includeReleased = arguments["includeReleased"] as? Bool ?? false
        let result = try thoughts(context).filter { thought in
            (laneID == nil || thought.lane?.id == laneID) && (includeCompleted || thought.completedAt == nil) && (includeReleased || thought.releasedAt == nil)
        }
        return ["lanes": allLanes.map(laneJSON), "thoughts": result.map(thoughtJSON)]
    }
    private func prioritized(context: ModelContext, arguments: [String: Any]) throws -> [String: Any] {
        let minimumPriority = PriorityLevel(rawValue: arguments["minimumPriority"] as? String ?? "low") ?? .low
        let result = try thoughts(context)
            .filter { $0.completedAt == nil && $0.releasedAt == nil && ThoughtAging.age(for: $0).priority.rank >= minimumPriority.rank }
            .sorted {
                let left = ThoughtAging.age(for: $0).priority.rank
                let right = ThoughtAging.age(for: $1).priority.rank
                return left == right ? $0.createdAt < $1.createdAt : left > right
            }
        return ["thoughts": result.map(thoughtJSON)]
    }
    private func search(context: ModelContext, arguments: [String: Any]) throws -> [String: Any] {
        guard let query = arguments["query"] as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError(message: "query is required") }
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return ["thoughts": try thoughts(context).filter { $0.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle) }.map(thoughtJSON)]
    }
    private func get(context: ModelContext, arguments: [String: Any]) throws -> [String: Any] { ["thought": thoughtJSON(try thought(context, id: id(arguments)))] }
    private func capture(context: ModelContext, arguments: [String: Any]) throws -> [String: Any] {
        guard let text = arguments["text"] as? String else { throw BridgeError(message: "text is required") }
        let target = if let raw = arguments["laneId"] as? String, let laneID = UUID(uuidString: raw) { try lane(context, id: laneID) } else { try lanes(context).first }
        guard let thought = try LaneManagement.capture(text, in: target, context: context, now: .now) else { throw BridgeError(message: "text cannot be empty") }
        return ["thought": thoughtJSON(thought)]
    }
    private func edit(context: ModelContext, arguments: [String: Any]) throws -> [String: Any] {
        guard let text = arguments["text"] as? String else { throw BridgeError(message: "text is required") }; let item = try thought(context, id: id(arguments))
        guard ThoughtManagement.edit(item, rawText: text, now: .now) else { throw BridgeError(message: "text cannot be empty") }; try context.save(); LanesNotificationBus.thoughtChanged(item.id); return ["thought": thoughtJSON(item)]
    }
    private func move(context: ModelContext, arguments: [String: Any]) throws -> [String: Any] { let item = try thought(context, id: id(arguments)); guard let raw = arguments["laneId"] as? String, let laneID = UUID(uuidString: raw) else { throw BridgeError(message: "laneId is required") }; guard ThoughtManagement.move(item, to: try lane(context, id: laneID), now: .now) else { throw BridgeError(message: "Thought is already in that lane") }; try context.save(); return ["thought": thoughtJSON(item)] }
    private func mark(context: ModelContext, arguments: [String: Any], release: Bool) throws -> [String: Any] { let item = try thought(context, id: id(arguments)); if release { ThoughtManagement.letGo(item, now: .now) } else { ThoughtManagement.complete(item, now: .now) }; try context.save(); LanesNotificationBus.thoughtChanged(item.id); return ["thought": thoughtJSON(item)] }
}

private enum PriorityLevel: String {
    case low, medium, high, urgent

    var rank: Int {
        switch self {
        case .low: 1
        case .medium: 2
        case .high: 3
        case .urgent: 4
        }
    }
}

private extension ThoughtAge {
    var name: String {
        switch self {
        case .fresh: "fresh"
        case .warm: "warm"
        case .attention: "attention"
        case .old: "old"
        }
    }

    var priority: PriorityLevel {
        switch self {
        case .fresh: .low
        case .warm: .medium
        case .attention: .high
        case .old: .urgent
        }
    }
}

private struct BridgeError: Error { let message: String }
private final class UnsafeArguments: @unchecked Sendable { let value: [String: Any]; init(_ value: [String: Any]) { self.value = value } }

/// A deliberately local, line-oriented JSON-RPC endpoint. The helper discovers the path from `socketPath`.
final class LanesMCPBridge: @unchecked Sendable {
    let socketPath: String
    private let service: LanesCommandService
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var clients: [Int32: DispatchSourceRead] = [:]
    private var buffers: [Int32: Data] = [:]

    init(service: LanesCommandService, socketPath: String? = nil) {
        self.service = service
        self.socketPath = socketPath ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("lanes/mcp.sock").path)
    }
    func start() {
        guard fd < 0 else { return }; try? FileManager.default.createDirectory(at: URL(fileURLWithPath: socketPath).deletingLastPathComponent(), withIntermediateDirectories: true); unlink(socketPath)
        fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); let pathCapacity = MemoryLayout.size(ofValue: address.sun_path); socketPath.withCString { path in withUnsafeMutablePointer(to: &address.sun_path) { ptr in ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { strncpy($0, path, pathCapacity - 1) } } }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1); withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = bind(fd, $0, length) } }; listen(fd, 8)
        let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated)); s.setEventHandler { [weak self] in self?.accept() }; s.setCancelHandler { [weak self] in if let fd = self?.fd { close(fd) } }; s.resume(); source = s
    }
    func stop() { source?.cancel(); source = nil; clients.values.forEach { $0.cancel() }; clients.removeAll(); buffers.removeAll(); if fd >= 0 { unlink(socketPath); fd = -1 } }
    private func accept() { let client = Darwin.accept(fd, nil, nil); guard client >= 0 else { return }; buffers[client] = Data(); let s = DispatchSource.makeReadSource(fileDescriptor: client, queue: .global(qos: .userInitiated)); s.setEventHandler { [weak self] in self?.read(client) }; s.setCancelHandler { close(client) }; clients[client] = s; s.resume() }
    private func read(_ client: Int32) { var bytes = [UInt8](repeating: 0, count: 65_536); let count = Darwin.read(client, &bytes, bytes.count); guard count > 0 else { clients[client]?.cancel(); return }; buffers[client, default: Data()].append(contentsOf: bytes[0..<count]); while let newline = buffers[client]!.firstIndex(of: 10) { let line = buffers[client]!.prefix(upTo: newline); buffers[client]!.removeSubrange(...newline); handle(line, client: client) } }
    private func handle(_ data: Data, client: Int32) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let id = object["id"] ?? NSNull(); let method = object["method"] as? String ?? ""
        guard UserDefaults.standard.bool(forKey: "mcpEnabled") else { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32001, "message": "MCP is disabled"]], client: client); return }
        if method == "tools/list" { send(["jsonrpc": "2.0", "id": id, "result": ["tools": Self.toolDefinitions()]], client: client); return }
        guard method == "tools/call" || method == "lanes.command", let params = object["params"] as? [String: Any] else { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown method"]], client: client); return }
        let rawName = (params["name"] as? String) ?? (params["command"] as? String) ?? ""
        let aliases = ["list_lanes": "lanes/list", "list_thoughts": "lanes/list", "list_prioritized_thoughts": "lanes/prioritized", "search": "lanes/search", "get": "lanes/get", "capture": "lanes/capture", "update_thought": "lanes/edit", "complete_thought": "lanes/complete", "release_thought": "lanes/release", "move_thought": "lanes/move"]
        guard let name = aliases[rawName] ?? (rawName.hasPrefix("lanes/") ? rawName : nil) else { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown command"]], client: client); return }
        var arguments = (params["arguments"] as? [String: Any]) ?? (params["args"] as? [String: Any]) ?? params
        if arguments["id"] == nil, let thoughtID = arguments["thoughtId"] { arguments["id"] = thoughtID }
        let boxedArguments = UnsafeArguments(arguments)
        DispatchQueue.main.async { [weak self, boxedArguments] in
            guard let self else { return }
            let resultData = MainActor.assumeIsolated { () -> Data in
                let result = self.service.call(name: name, arguments: boxedArguments.value)
                return (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
            }
            let result = (try? JSONSerialization.jsonObject(with: resultData)) ?? [:]
            self.send(["jsonrpc": "2.0", "id": id, "result": ["structuredContent": result, "content": [["type": "text", "text": String(data: resultData, encoding: .utf8) ?? "{}"]]]], client: client)
        }
    }
    private func send(_ response: [String: Any], client: Int32) { if let out = try? JSONSerialization.data(withJSONObject: response) { var line = out; line.append(10); _ = line.withUnsafeBytes { Darwin.write(client, $0.baseAddress, line.count) } } }
    static func toolDefinitions() -> [[String: Any]] { [
        ("list_lanes", "List lanes"), ("list_thoughts", "List thoughts"), ("list_prioritized_thoughts", "List active thoughts ordered by their age-derived priority"), ("search", "Search thoughts"), ("get", "Get a thought"),
        ("capture", "Capture a thought"), ("update_thought", "Edit a thought"), ("move_thought", "Move a thought"),
        ("complete_thought", "Complete a thought"), ("release_thought", "Release a thought")
    ].map { ["name": $0.0, "description": $0.1] } }
}
