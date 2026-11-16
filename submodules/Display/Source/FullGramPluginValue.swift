import Foundation

public enum FullGramPluginLanguage: String, Codable, CaseIterable {
    case lua
    case python

    public var displayName: String {
        switch self {
        case .lua: return "Lua"
        case .python: return "Python"
        }
    }

    public var fileExtension: String {
        switch self {
        case .lua: return "lua"
        case .python: return "py"
        }
    }
}

public struct FullGramPluginMetadata: Codable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var author: String
    public var description: String
    public var permissions: [String]

    public var hasNetworkPermission: Bool {
        return self.permissions.contains("net")
    }

    public init(id: String, name: String, version: String = "1.0", author: String = "User", description: String = "", permissions: [String] = []) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.permissions = permissions
    }

    public static func parse(from code: String, fallbackName: String, language: FullGramPluginLanguage) -> FullGramPluginMetadata {
        let commentPrefix = language == .lua ? "--" : "#"
        var name = fallbackName
        var id = ""
        var version = "1.0"
        var author = "User"
        var description = ""
        var permissions: [String] = []

        for rawLine in code.components(separatedBy: .newlines).prefix(30) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(commentPrefix) else { continue }
            let body = trimmed.dropFirst(commentPrefix.count).trimmingCharacters(in: .whitespaces)
            if let val = extractTag("@name", from: body) { name = val }
            else if let val = extractTag("@id", from: body) { id = val }
            else if let val = extractTag("@version", from: body) { version = val }
            else if let val = extractTag("@author", from: body) { author = val }
            else if let val = extractTag("@description", from: body) { description = val }
            else if let val = extractTag("@permission", from: body) ?? extractTag("@permissions", from: body) {
                let parsed = val
                    .lowercased()
                    .components(separatedBy: CharacterSet(charactersIn: ",; \t"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for p in parsed where !permissions.contains(p) {
                    permissions.append(p)
                }
            }
        }

        if id.isEmpty {
            let clean = name.lowercased().replacingOccurrences(of: "[^a-z0-9_]+", with: "_", options: .regularExpression)
            id = clean.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            if id.isEmpty {
                id = "plugin_\(abs(name.hashValue) % 100000)"
            }
        }
        return FullGramPluginMetadata(id: id, name: name, version: version, author: author, description: description, permissions: permissions)
    }

    private static func extractTag(_ tag: String, from line: String) -> String? {
        guard line.lowercased().hasPrefix(tag) else { return nil }
        let rest = line.dropFirst(tag.count).trimmingCharacters(in: .whitespaces)
        let stripped = rest.hasPrefix(":") ? rest.dropFirst().trimmingCharacters(in: .whitespaces) : rest
        return stripped.isEmpty ? nil : stripped
    }
}

public struct FullGramPluginDescriptor: Codable, Equatable {
    public var id: String
    public var name: String
    public var language: FullGramPluginLanguage
    public var version: String
    public var author: String
    public var description: String
    public var code: String
    public var isEnabled: Bool
    public var isBuiltIn: Bool
    public var updatedAt: TimeInterval

    public init(
        id: String,
        name: String,
        language: FullGramPluginLanguage,
        version: String = "1.0",
        author: String = "User",
        description: String = "",
        code: String,
        isEnabled: Bool = false,
        isBuiltIn: Bool = false,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.version = version
        self.author = author
        self.description = description
        self.code = code
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.updatedAt = updatedAt
    }
}

public enum FullGramPluginOutgoingDecision: Equatable {
    case pass
    case replaceText(String)
    case cancel(toast: String?)
}

public final class FullGramPluginTableBox {
    public var arrayPart: [FullGramPluginValue] = []
    public var mapPart: [String: FullGramPluginValue] = [:]
    public var orderedKeys: [String] = []

    public init() {}

    public convenience init(array: [FullGramPluginValue]) {
        self.init()
        self.arrayPart = array
    }

    public convenience init(dict: [String: FullGramPluginValue]) {
        self.init()
        for (k, v) in dict {
            self.set(key: .string(k), value: v)
        }
    }

    public func get(key: FullGramPluginValue) -> FullGramPluginValue {
        switch key {
        case let .int(i):
            let idx = Int(i) - 1 // 1-based for Lua arrays if positive
            if idx >= 0 && idx < self.arrayPart.count {
                return self.arrayPart[idx]
            }
            return self.mapPart[String(i)] ?? .nil
        case let .string(s):
            return self.mapPart[s] ?? .nil
        case let .double(d):
            if d == d.rounded(), let idx = Int64(exactly: d) {
                return self.get(key: .int(idx))
            }
            return self.mapPart[String(d)] ?? .nil
        default:
            return self.mapPart[key.asString] ?? .nil
        }
    }

    public func set(key: FullGramPluginValue, value: FullGramPluginValue) {
        switch key {
        case let .int(i):
            let idx = Int(i) - 1
            if idx >= 0 && idx < self.arrayPart.count {
                self.arrayPart[idx] = value
                return
            } else if idx == self.arrayPart.count {
                if case .nil = value { return }
                self.arrayPart.append(value)
                return
            }
            let s = String(i)
            self.setMapKey(s, value: value)
        case let .string(s):
            self.setMapKey(s, value: value)
        default:
            self.setMapKey(key.asString, value: value)
        }
    }

    private func setMapKey(_ key: String, value: FullGramPluginValue) {
        if case .nil = value {
            self.mapPart.removeValue(forKey: key)
            self.orderedKeys.removeAll { $0 == key }
        } else {
            if self.mapPart[key] == nil {
                self.orderedKeys.append(key)
            }
            self.mapPart[key] = value
        }
    }
}

public indirect enum FullGramPluginValue {
    case `nil`
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case table(FullGramPluginTableBox)
    case list([FullGramPluginValue])
    case function(([FullGramPluginValue]) throws -> FullGramPluginValue)

    public var isTruthy: Bool {
        switch self {
        case .nil: return false
        case let .bool(b): return b
        case let .int(i): return i != 0
        case let .double(d): return d != 0.0
        case let .string(s): return !s.isEmpty
        case let .list(arr): return !arr.isEmpty
        case let .table(box): return !(box.arrayPart.isEmpty && box.mapPart.isEmpty)
        case .function: return true
        }
    }

    public var isLuaTruthy: Bool {
        switch self {
        case .nil: return false
        case let .bool(b): return b
        default: return true
        }
    }

    public var asInt: Int64? {
        switch self {
        case let .int(i): return i
        case let .double(d): return Int64(d)
        case let .bool(b): return b ? 1 : 0
        case let .string(s): return Int64(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var asDouble: Double? {
        switch self {
        case let .int(i): return Double(i)
        case let .double(d): return d
        case let .bool(b): return b ? 1.0 : 0.0
        case let .string(s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var asString: String {
        switch self {
        case .nil: return "nil"
        case let .bool(b): return b ? "true" : "false"
        case let .int(i): return String(i)
        case let .double(d):
            if d == d.rounded() && abs(d) < 1e15 {
                return String(Int64(d))
            }
            return String(d)
        case let .string(s): return s
        case .table: return "<table>"
        case let .list(arr):
            return "[" + arr.map { $0.asString }.joined(separator: ", ") + "]"
        case .function: return "<function>"
        }
    }

    public func toJSONObject() -> Any {
        switch self {
        case .nil: return NSNull()
        case let .bool(b): return b
        case let .int(i): return i
        case let .double(d): return d
        case let .string(s): return s
        case let .list(arr): return arr.map { $0.toJSONObject() }
        case let .table(box):
            if box.mapPart.isEmpty {
                return box.arrayPart.map { $0.toJSONObject() }
            }
            var dict: [String: Any] = [:]
            for (k, v) in box.mapPart {
                dict[k] = v.toJSONObject()
            }
            for (i, v) in box.arrayPart.enumerated() {
                dict[String(i + 1)] = v.toJSONObject()
            }
            return dict
        case .function:
            return "<function>"
        }
    }

    public static func fromJSONObject(_ obj: Any, forPython: Bool = false) -> FullGramPluginValue {
        if obj is NSNull { return .nil }
        if let n = obj as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            let d = n.doubleValue
            if d == d.rounded() && abs(d) < Double(Int64.max / 2) {
                return .int(n.int64Value)
            }
            return .double(d)
        }
        if let s = obj as? String { return .string(s) }
        if let arr = obj as? [Any] {
            let mapped = arr.map { fromJSONObject($0, forPython: forPython) }
            return forPython ? .list(mapped) : .table(FullGramPluginTableBox(array: mapped))
        }
        if let dict = obj as? [String: Any] {
            var map: [String: FullGramPluginValue] = [:]
            for (k, v) in dict {
                map[k] = fromJSONObject(v, forPython: forPython)
            }
            return .table(FullGramPluginTableBox(dict: map))
        }
        return .string(String(describing: obj))
    }
}

public struct FullGramPluginError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { return self.message }
}
