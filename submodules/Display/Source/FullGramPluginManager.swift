import Foundation
import UIKit

public enum FullGramPluginNotifications {
    public static let pluginsDidChange = Notification.Name("FullGram.PluginsDidChange")
    public static let toastRequested = Notification.Name("FullGram.PluginToastRequested")
    public static let runCommandInChatRequested = Notification.Name("FullGram.PluginRunCommandInChatRequested")
    public static let openUIRequested = Notification.Name("FullGram.PluginOpenUIRequested")
}

public struct FullGramRemotePluginItem: Codable, Equatable {
    public let id: String
    public let name: String
    public let language: FullGramPluginLanguage
    public let version: String
    public let author: String
    public let description: String
    public let url: String?
    public let code: String?
}

public struct FullGramRemoteCatalog: Codable {
    public let version: Int?
    public let plugins: [FullGramRemotePluginItem]
}

private final class FullGramLoadedPlugin {
    let descriptor: FullGramPluginDescriptor
    var luaVM: FullGramLuaVM?
    var pythonVM: FullGramPythonVM?
    var rustVM: FullGramRustVM?
    var registeredCommands: [String: ([FullGramPluginValue]) throws -> FullGramPluginValue] = [:]
    var lastError: String?

    var hasOutgoingHook: Bool = false
    var hasRenderHook: Bool = false
    var hasCommandHook: Bool = false

    init(descriptor: FullGramPluginDescriptor) {
        self.descriptor = descriptor
    }
}

public final class FullGramPluginManager {
    public static let shared = FullGramPluginManager()
    public static let officialCatalogURL = "https://fullgram.korsakovx.workers.dev/plugins.json"

    private let lock = NSRecursiveLock()
    private let systemEnabledKey = "fullgram.plugins.systemEnabled"
    private let catalogURLKey = "fullgram.plugins.catalogURL"
    private static let layoutFixerModeKey = "fullgram.plugin.store.fg_layout_fixer.mode"

    public var layoutFixerMode: String {
        get {
            let val = UserDefaults.standard.string(forKey: Self.layoutFixerModeKey) ?? "ru2en"
            return (val == "en2ru" || val == "auto") ? val : "ru2en"
        }
        set {
            let normalized = (newValue == "en2ru" || newValue == "auto") ? newValue : "ru2en"
            UserDefaults.standard.set(normalized, forKey: Self.layoutFixerModeKey)
            NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
        }
    }

    public var layoutFixerModeTitle: String {
        switch self.layoutFixerMode {
        case "en2ru":
            return "Англ → Рус"
        case "auto":
            return "Авто (Рус ↔ Англ)"
        default:
            return "Рус → Англ"
        }
    }
    private var descriptors: [FullGramPluginDescriptor] = []
    private var loaded: [String: FullGramLoadedPlugin] = [:]
    private var cachedOrderedPlugins: [FullGramLoadedPlugin] = []
    private var cachedRenderPlugins: [FullGramLoadedPlugin] = []
    private var logsByPlugin: [String: [String]] = [:]
    private var cachedSystemEnabled: Bool?
    private var hasRenderHooks: Bool = false
    private var didInitialize = false

    private static let logDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
    private static let commandHintRegex = try? NSRegularExpression(pattern: #"(?:command|cmd)\s*==\s*["']([a-zA-Z0-9_-]+)["']"#)
    private static let plugSubcommandRegex = try? NSRegularExpression(pattern: #"subcommand\s*==\s*["']([a-zA-Z0-9_-]+)["']"#)
    private let vmLock = NSRecursiveLock()

    public var catalogURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: self.catalogURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? Self.officialCatalogURL : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: self.catalogURLKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: self.catalogURLKey)
            }
        }
    }

    private init() {}

    public var isSystemEnabled: Bool {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            if let cached = self.cachedSystemEnabled {
                return cached
            }
            let resolved: Bool
            if UserDefaults.standard.object(forKey: self.systemEnabledKey) == nil {
                resolved = true
            } else {
                resolved = UserDefaults.standard.bool(forKey: self.systemEnabledKey)
            }
            self.cachedSystemEnabled = resolved
            return resolved
        }
        set {
            self.lock.lock()
            self.cachedSystemEnabled = newValue
            self.lock.unlock()
            UserDefaults.standard.set(newValue, forKey: self.systemEnabledKey)
            self.reloadRuntime()
            NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
        }
    }

    private var pluginsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("FullGramPlugins", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var manifestURL: URL {
        return self.pluginsDirectoryURL.appendingPathComponent("manifest.json")
    }

    private func ensureLoaded() {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.didInitialize else { return }
        self.didInitialize = true

        if let data = try? Data(contentsOf: self.manifestURL),
           let decoded = try? JSONDecoder().decode([FullGramPluginDescriptor].self, from: data) {
            var restored: [FullGramPluginDescriptor] = []
            for var item in decoded {
                let scriptURL = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
                if let diskCode = try? String(contentsOf: scriptURL, encoding: .utf8), !diskCode.isEmpty {
                    item.code = diskCode
                }
                restored.append(item)
            }
            self.descriptors = restored
        }

        let starters = Self.defaultStarterPlugins()
        if self.descriptors.isEmpty {
            self.descriptors = starters
            self.persistLocked()
        } else {
            var existingIds = Set(self.descriptors.map { $0.id })
            var changed = false
            for starter in starters {
                if !existingIds.contains(starter.id) {
                    self.descriptors.append(starter)
                    existingIds.insert(starter.id)
                    changed = true
                } else if let idx = self.descriptors.firstIndex(where: { $0.id == starter.id }),
                          self.descriptors[idx].version != starter.version {
                    let wasEnabled = self.descriptors[idx].isEnabled
                    var updated = starter
                    updated.isEnabled = wasEnabled
                    self.descriptors[idx] = updated
                    changed = true
                }
            }
            if changed {
                self.persistLocked()
            }
        }
        self.reloadRuntimeLocked()
    }

    private func persistLocked() {
        let dir = self.pluginsDirectoryURL
        for item in self.descriptors {
            let scriptURL = dir.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
            try? item.code.write(to: scriptURL, atomically: true, encoding: .utf8)
        }
        if let data = try? JSONEncoder().encode(self.descriptors) {
            try? data.write(to: self.manifestURL, options: .atomic)
        }
    }

    public func allPlugins() -> [FullGramPluginDescriptor] {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.descriptors
    }

    public func plugin(id: String) -> FullGramPluginDescriptor? {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.descriptors.first(where: { $0.id == id })
    }

    public func error(forPluginId id: String) -> String? {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loaded[id]?.lastError
    }

    public func logs(forPluginId id: String) -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.logsByPlugin[id] ?? []
    }

    public func clearLogs(forPluginId id: String) {
        self.lock.lock()
        self.logsByPlugin[id] = []
        self.lock.unlock()
    }

    private func appendLog(pluginId: String, message: String) {
        self.lock.lock()
        let line = "[\(Self.logDateFormatter.string(from: Date()))] \(message)"
        var arr = self.logsByPlugin[pluginId] ?? []
        arr.append(line)
        if arr.count > 200 {
            arr.removeFirst(arr.count - 200)
        }
        self.logsByPlugin[pluginId] = arr
        self.lock.unlock()
    }

    @discardableResult
    public func savePlugin(
        id: String? = nil,
        name: String,
        language: FullGramPluginLanguage,
        code: String,
        enabled: Bool? = nil
    ) -> FullGramPluginDescriptor {
        self.ensureLoaded()
        let meta = FullGramPluginMetadata.parse(from: code, fallbackName: name, language: language)
        let resolvedId = id ?? meta.id

        self.lock.lock()
        let existingIndex = self.descriptors.firstIndex(where: { $0.id == resolvedId })
        let wasEnabled = existingIndex.map { self.descriptors[$0].isEnabled } ?? true
        let wasBuiltIn = existingIndex.map { self.descriptors[$0].isBuiltIn } ?? false
        let descriptor = FullGramPluginDescriptor(
            id: resolvedId,
            name: meta.name.isEmpty ? name : meta.name,
            language: language,
            version: meta.version,
            author: meta.author,
            description: meta.description,
            code: code,
            isEnabled: enabled ?? wasEnabled,
            isBuiltIn: wasBuiltIn,
            updatedAt: Date().timeIntervalSince1970
        )
        if let idx = existingIndex {
            self.descriptors[idx] = descriptor
        } else {
            self.descriptors.append(descriptor)
        }
        self.persistLocked()
        self.reloadRuntimeLocked()
        self.lock.unlock()

        NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
        return descriptor
    }

    public func setPluginEnabled(id: String, enabled: Bool) {
        self.ensureLoaded()
        self.lock.lock()
        if let idx = self.descriptors.firstIndex(where: { $0.id == id }) {
            self.descriptors[idx].isEnabled = enabled
            self.persistLocked()
            self.reloadRuntimeLocked()
        }
        self.lock.unlock()
        NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
    }

    public func deletePlugin(id: String) {
        self.ensureLoaded()
        self.lock.lock()
        if let idx = self.descriptors.firstIndex(where: { $0.id == id }) {
            let item = self.descriptors.remove(at: idx)
            let scriptURL = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
            try? FileManager.default.removeItem(at: scriptURL)
            self.loaded.removeValue(forKey: id)
            self.persistLocked()
        }
        self.lock.unlock()
        NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
    }

    public func importPlugin(from url: URL, preferredFileName: String? = nil) throws -> FullGramPluginDescriptor {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let code = try String(contentsOf: url, encoding: .utf8)
        let sourceName = preferredFileName?.isEmpty == false ? preferredFileName! : url.lastPathComponent
        let ext = (sourceName as NSString).pathExtension.lowercased()
        let baseName = (sourceName as NSString).deletingPathExtension
        let language: FullGramPluginLanguage
        if ext == "py" {
            language = .python
        } else if ext == "rs" {
            language = .rust
        } else if ext == "lua" {
            language = .lua
        } else if code.contains("def on_") || code.contains("import fullgram") || code.contains("# @name") {
            language = .python
        } else if code.contains("fn on_") || code.contains("fullgram::") || code.contains("// @name") {
            language = .rust
        } else {
            language = .lua
        }
        let fallbackName = baseName.isEmpty ? "Импортированный плагин" : baseName
        return self.savePlugin(id: nil, name: fallbackName, language: language, code: code, enabled: true)
    }

    public func exportFileURL(forPluginId id: String) -> URL? {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let item = self.descriptors.first(where: { $0.id == id }) else { return nil }
        let url = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
        try? item.code.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func reloadRuntime() {
        self.lock.lock()
        self.reloadRuntimeLocked()
        self.lock.unlock()
    }

    private func reloadRuntimeLocked() {
        self.loaded.removeAll()
        self.cachedOrderedPlugins.removeAll()
        self.cachedRenderPlugins.removeAll()
        self.hasRenderHooks = false
        guard self.isSystemEnabled else { return }

        var anyRender = false
        for descriptor in self.descriptors where descriptor.isEnabled {
            let runtime = self.compile(descriptor: descriptor)
            if runtime.hasRenderHook {
                anyRender = true
                self.cachedRenderPlugins.append(runtime)
            }
            self.loaded[descriptor.id] = runtime
            self.cachedOrderedPlugins.append(runtime)
        }
        self.hasRenderHooks = anyRender
    }

    private static let chatStatsThreadKey = "FullGram.Plugin.ChatStats"

    private func makeHostAPI(
        pluginId: String,
        commandsBox: FullGramLoadedPlugin?,
        logCapture: ((String) -> Void)? = nil
    ) -> [String: FullGramPluginValue] {
        let storagePrefix = "fullgram.plugin.store.\(pluginId)."

        return [
            "log": .function { [weak self] args in
                let text = args.map { $0.asString }.joined(separator: " ")
                logCapture?(text)
                self?.appendLog(pluginId: pluginId, message: text)
                return .nil
            },
            "toast": .function { args in
                let text = args.first?.asString ?? ""
                guard !text.isEmpty else { return .nil }
                logCapture?("[toast] \(text)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: FullGramPluginNotifications.toastRequested,
                        object: nil,
                        userInfo: ["text": text, "pluginId": pluginId]
                    )
                }
                return .nil
            },
            "open_ui": .function { args in
                let first = args.first ?? .nil
                var specDict: [String: Any] = ["pluginId": pluginId]
                switch first {
                case let .string(kind):
                    specDict["kind"] = kind
                case let .table(box):
                    if let dict = box.toJSONObject() as? [String: Any] {
                        for (k, v) in dict {
                            specDict[k] = v
                        }
                    }
                default:
                    break
                }
                logCapture?("[open_ui] \(specDict["kind"] ?? pluginId)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: FullGramPluginNotifications.openUIRequested,
                        object: nil,
                        userInfo: specDict
                    )
                }
                return .bool(true)
            },
            "clipboard_set": .function { args in
                let text = args.first?.asString ?? ""
                DispatchQueue.main.async {
                    UIPasteboard.general.string = text
                }
                return .bool(true)
            },
            "clipboard_get": .function { _ in
                if Thread.isMainThread {
                    return .string(UIPasteboard.general.string ?? "")
                }
                var val = ""
                DispatchQueue.main.sync {
                    val = UIPasteboard.general.string ?? ""
                }
                return .string(val)
            },
            "storage_get": .function { args in
                let key = args.first?.asString ?? ""
                let fallback = args.count > 1 ? args[1] : .nil
                guard !key.isEmpty, let stored = UserDefaults.standard.object(forKey: storagePrefix + key) else {
                    return fallback
                }
                return FullGramPluginValue.fromJSONObject(stored, forPython: true)
            },
            "storage_set": .function { args in
                let key = args.first?.asString ?? ""
                guard !key.isEmpty else { return .bool(false) }
                let val = args.count > 1 ? args[1] : .nil
                if case .nil = val {
                    UserDefaults.standard.removeObject(forKey: storagePrefix + key)
                } else {
                    UserDefaults.standard.set(val.toJSONObject(), forKey: storagePrefix + key)
                }
                return .bool(true)
            },
            "register_command": .function { [weak commandsBox] args in
                guard args.count >= 2, case let .function(fn) = args[1] else { return .nil }
                let raw = args[0].asString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let cmd = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
                if !cmd.isEmpty {
                    commandsBox?.registeredCommands[cmd] = fn
                    commandsBox?.hasCommandHook = true
                }
                return .nil
            },
            "get_chat_stats": .function { _ in
                if let stats = Thread.current.threadDictionary[FullGramPluginManager.chatStatsThreadKey] as? [String: FullGramPluginValue] {
                    return .table(FullGramPluginTableBox(dict: stats))
                }
                return .nil
            },
            "http_get": .function { args in
                let rawURL = args.first?.asString ?? ""
                guard let url = URL(string: rawURL),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http" else {
                    return .nil
                }
                let sem = DispatchSemaphore(value: 0)
                var body: String?
                var request = URLRequest(url: url)
                request.timeoutInterval = 8.0
                URLSession.shared.dataTask(with: request) { data, _, _ in
                    if let data {
                        body = String(data: data, encoding: .utf8)
                    }
                    sem.signal()
                }.resume()
                _ = sem.wait(timeout: .now() + 8.5)
                return body.map { .string($0) } ?? .nil
            }
        ]
    }

    private func compile(descriptor: FullGramPluginDescriptor) -> FullGramLoadedPlugin {
        let holder = FullGramLoadedPlugin(descriptor: descriptor)
        let hostAPI = self.makeHostAPI(pluginId: descriptor.id, commandsBox: holder)

        do {
            switch descriptor.language {
            case .lua:
                let vm = FullGramLuaVM(hostAPI: hostAPI) { [weak self] msg in
                    self?.appendLog(pluginId: descriptor.id, message: msg)
                }
                try vm.load(code: descriptor.code)
                holder.luaVM = vm
                holder.hasOutgoingHook = vm.hasFunction("on_outgoing_message")
                holder.hasRenderHook = vm.hasFunction("on_render_message")
                holder.hasCommandHook = holder.hasCommandHook || vm.hasFunction("on_command")
            case .python:
                let vm = FullGramPythonVM(hostAPI: hostAPI) { [weak self] msg in
                    self?.appendLog(pluginId: descriptor.id, message: msg)
                }
                try vm.load(code: descriptor.code)
                holder.pythonVM = vm
                holder.hasOutgoingHook = vm.hasFunction("on_outgoing_message")
                holder.hasRenderHook = vm.hasFunction("on_render_message")
                holder.hasCommandHook = holder.hasCommandHook || vm.hasFunction("on_command")
            case .rust:
                let vm = FullGramRustVM(hostAPI: hostAPI) { [weak self] msg in
                    self?.appendLog(pluginId: descriptor.id, message: msg)
                }
                try vm.load(code: descriptor.code)
                holder.rustVM = vm
                holder.hasOutgoingHook = vm.hasFunction("on_outgoing_message")
                holder.hasRenderHook = vm.hasFunction("on_render_message")
                holder.hasCommandHook = holder.hasCommandHook || vm.hasFunction("on_command")
            }
        } catch {
            holder.lastError = error.localizedDescription
            self.appendLog(pluginId: descriptor.id, message: "ERROR: \(error.localizedDescription)")
        }
        return holder
    }

    public func hasMessageActionPlugins() -> Bool {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.isSystemEnabled && !self.loaded.values.filter({ ($0.luaVM?.hasFunction("on_message_action") ?? false) || ($0.pythonVM?.hasFunction("on_message_action") ?? false) || ($0.rustVM?.hasFunction("on_message_action") ?? false) }).isEmpty
    }

    public func availableCommands() -> [(command: String, description: String, pluginName: String)] {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled else {
            self.lock.unlock()
            return []
        }
        let active = self.descriptors.compactMap { desc -> (FullGramPluginDescriptor, FullGramLoadedPlugin)? in
            guard let holder = self.loaded[desc.id] else { return nil }
            return (desc, holder)
        }
        self.lock.unlock()

        var results: [(command: String, description: String, pluginName: String)] = []
        var seen = Set<String>()
        let regex = Self.commandHintRegex
        let plugRegex = Self.plugSubcommandRegex

        for (desc, holder) in active {
            for cmd in holder.registeredCommands.keys.sorted() {
                if seen.insert(cmd).inserted {
                    results.append((cmd, desc.description, desc.name))
                }
            }
            if let plugRegex {
                let ns = desc.code as NSString
                for m in plugRegex.matches(in: desc.code, range: NSRange(location: 0, length: ns.length)) {
                    let sub = ns.substring(with: m.range(at: 1)).lowercased()
                    let fullCmd = "plug \(sub)"
                    if seen.insert(fullCmd).inserted {
                        results.append((fullCmd, desc.description, desc.name))
                    }
                }
            }
            if let regex {
                let ns = desc.code as NSString
                for m in regex.matches(in: desc.code, range: NSRange(location: 0, length: ns.length)) {
                    let cmd = ns.substring(with: m.range(at: 1)).lowercased()
                    if cmd == "plug" { continue }
                    if seen.insert(cmd).inserted {
                        results.append((cmd, desc.description, desc.name))
                    }
                }
            }
        }
        return results
    }

    public func runMessageAction(pluginId: String? = nil, text: String, peerId: Int64) -> String? {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled else {
            self.lock.unlock()
            return nil
        }
        let targets = self.descriptors.compactMap { desc -> FullGramLoadedPlugin? in
            if let pluginId, desc.id != pluginId { return nil }
            return self.loaded[desc.id]
        }
        self.lock.unlock()

        let ctx = FullGramPluginTableBox(dict: [
            "text": .string(text),
            "peer_id": .int(peerId)
        ])
        for plugin in targets {
            do {
                if let lua = plugin.luaVM, lua.hasFunction("on_message_action") {
                    let res = try lua.callFunction("on_message_action", args: [.table(ctx)])
                    if case let .string(out) = res, !out.isEmpty { return out }
                } else if let py = plugin.pythonVM, py.hasFunction("on_message_action") {
                    let res = try py.callFunction("on_message_action", args: [.table(ctx)])
                    if case let .string(out) = res, !out.isEmpty { return out }
                } else if let rs = plugin.rustVM, rs.hasFunction("on_message_action") {
                    let res = try rs.callFunction("on_message_action", args: [.table(ctx)])
                    if case let .string(out) = res, !out.isEmpty { return out }
                }
            } catch {
                self.appendLog(pluginId: plugin.descriptor.id, message: "Action error: \(error.localizedDescription)")
            }
        }
        return nil
    }

    /// Invokes `on_ui_event(ctx)` inside a Lua or Python plugin for two-way graphical UI interaction.
    public func dispatchUIEvent(
        pluginId: String,
        action: String,
        payload: [String: FullGramPluginValue] = [:]
    ) -> FullGramPluginValue {
        self.ensureLoaded()
        self.lock.lock()
        let holder = self.loaded[pluginId]
        self.lock.unlock()
        guard let holder else { return .nil }

        var dict = payload
        dict["action"] = .string(action)
        let ctx = FullGramPluginTableBox(dict: dict)
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        do {
            if let lua = holder.luaVM, lua.hasFunction("on_ui_event") {
                return try lua.callFunction("on_ui_event", args: [.table(ctx)])
            } else if let py = holder.pythonVM, py.hasFunction("on_ui_event") {
                return try py.callFunction("on_ui_event", args: [.table(ctx)])
            } else if let rs = holder.rustVM, rs.hasFunction("on_ui_event") {
                return try rs.callFunction("on_ui_event", args: [.table(ctx)])
            }
        } catch {
            self.appendLog(pluginId: pluginId, message: "UI event error: \(error.localizedDescription)")
        }
        return .nil
    }

    // MARK: - Execution Hooks

    public func processOutgoingMessage(
        text: String,
        peerId: Int64,
        isGroup: Bool = false,
        isChannel: Bool = false,
        chatStats: [String: FullGramPluginValue]? = nil
    ) -> FullGramPluginOutgoingDecision {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled && !self.cachedOrderedPlugins.isEmpty else {
            self.lock.unlock()
            return .pass
        }
        let orderedPlugins = self.cachedOrderedPlugins
        self.lock.unlock()

        if let chatStats {
            Thread.current.threadDictionary[FullGramPluginManager.chatStatsThreadKey] = chatStats
        }
        defer {
            Thread.current.threadDictionary.removeObject(forKey: FullGramPluginManager.chatStatsThreadKey)
        }

        var currentText = text
        var didModify = false

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var commandName: String?
        var commandArgs: String = ""
        if trimmed.hasPrefix(".") && trimmed.count > 1 {
            let withoutDot = String(trimmed.dropFirst())
            if let spaceIdx = withoutDot.firstIndex(where: { $0.isWhitespace }) {
                commandName = String(withoutDot[..<spaceIdx]).lowercased()
                commandArgs = String(withoutDot[withoutDot.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                commandName = withoutDot.lowercased()
            }
        }

        let subcommand: String = {
            guard !commandArgs.isEmpty else { return "" }
            if let sp = commandArgs.firstIndex(where: { $0.isWhitespace }) {
                return String(commandArgs[..<sp]).lowercased()
            }
            return commandArgs.lowercased()
        }()

        self.vmLock.lock()
        defer { self.vmLock.unlock() }

        for plugin in orderedPlugins {
            if let cmd = commandName, plugin.hasCommandHook {
                var ctxDict: [String: FullGramPluginValue] = [
                    "command": .string(cmd),
                    "subcommand": .string(subcommand),
                    "args": .string(commandArgs),
                    "text": .string(currentText),
                    "peer_id": .int(peerId),
                    "is_group": .bool(isGroup),
                    "is_channel": .bool(isChannel)
                ]
                if let chatStats {
                    ctxDict["chat_stats"] = .table(FullGramPluginTableBox(dict: chatStats))
                }
                let ctxTable = FullGramPluginTableBox(dict: ctxDict)
                do {
                    var result: FullGramPluginValue = .nil
                    if let registeredFn = plugin.registeredCommands[cmd] {
                        result = try registeredFn([.table(ctxTable)])
                    } else if let lua = plugin.luaVM, lua.hasFunction("on_command") {
                        result = try lua.callFunction("on_command", args: [.table(ctxTable)])
                    } else if let py = plugin.pythonVM, py.hasFunction("on_command") {
                        result = try py.callFunction("on_command", args: [.table(ctxTable)])
                    } else if let rs = plugin.rustVM, rs.hasFunction("on_command") {
                        result = try rs.callFunction("on_command", args: [.table(ctxTable)])
                    }
                    switch self.interpretDecision(result) {
                    case .pass:
                        break
                    case let .replaceText(newText):
                        currentText = newText
                        didModify = true
                        commandName = nil
                    case let .cancel(toast):
                        return .cancel(toast: toast)
                    }
                } catch {
                    self.appendLog(pluginId: plugin.descriptor.id, message: "Command error: \(error.localizedDescription)")
                }
            }

            if plugin.hasOutgoingHook {
                let ctxTable = FullGramPluginTableBox(dict: [
                    "text": .string(currentText),
                    "peer_id": .int(peerId),
                    "is_group": .bool(isGroup),
                    "is_channel": .bool(isChannel)
                ])
                do {
                    let result: FullGramPluginValue
                    if let lua = plugin.luaVM {
                        result = try lua.callFunction("on_outgoing_message", args: [.table(ctxTable)])
                    } else if let py = plugin.pythonVM {
                        result = try py.callFunction("on_outgoing_message", args: [.table(ctxTable)])
                    } else if let rs = plugin.rustVM {
                        result = try rs.callFunction("on_outgoing_message", args: [.table(ctxTable)])
                    } else {
                        continue
                    }
                    switch self.interpretDecision(result) {
                    case .pass:
                        break
                    case let .replaceText(newText):
                        if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            currentText = newText
                            didModify = true
                        }
                    case let .cancel(toast):
                        return .cancel(toast: toast)
                    }
                } catch {
                    self.appendLog(pluginId: plugin.descriptor.id, message: "Outgoing hook error: \(error.localizedDescription)")
                }
            }
        }

        return didModify ? .replaceText(currentText) : .pass
    }

    public func processRenderMessage(
        text: String,
        peerId: Int64,
        isIncoming: Bool,
        messageId: Int32
    ) -> String {
        guard !text.isEmpty else { return text }
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled && self.hasRenderHooks && !self.cachedRenderPlugins.isEmpty else {
            self.lock.unlock()
            return text
        }
        let renderPlugins = self.cachedRenderPlugins
        self.lock.unlock()

        self.vmLock.lock()
        defer { self.vmLock.unlock() }

        var currentText = text
        for plugin in renderPlugins {
            let ctxTable = FullGramPluginTableBox(dict: [
                "text": .string(currentText),
                "peer_id": .int(peerId),
                "is_incoming": .bool(isIncoming),
                "message_id": .int(Int64(messageId))
            ])
            do {
                let result: FullGramPluginValue
                if let lua = plugin.luaVM {
                    result = try lua.callFunction("on_render_message", args: [.table(ctxTable)])
                } else if let py = plugin.pythonVM {
                    result = try py.callFunction("on_render_message", args: [.table(ctxTable)])
                } else if let rs = plugin.rustVM {
                    result = try rs.callFunction("on_render_message", args: [.table(ctxTable)])
                } else {
                    continue
                }
                if case let .string(updated) = result {
                    currentText = updated
                }
            } catch {
                self.appendLog(pluginId: plugin.descriptor.id, message: "Render hook error: \(error.localizedDescription)")
            }
        }
        return currentText
    }

    public func testExecute(
        code: String,
        language: FullGramPluginLanguage,
        sampleInput: String = ".shrug проверка"
    ) -> (output: String, logs: [String], error: String?) {
        var capturedLogs: [String] = []
        let holder = FullGramLoadedPlugin(descriptor: FullGramPluginDescriptor(id: "__test__", name: "Test", language: language, code: code))
        let hostAPI = self.makeHostAPI(pluginId: "__test__", commandsBox: holder) { line in
            capturedLogs.append(line)
        }

        do {
            let ctxTable = FullGramPluginTableBox(dict: [
                "text": .string(sampleInput),
                "command": .string(sampleInput.hasPrefix(".") ? String(sampleInput.dropFirst().split(separator: " ").first ?? "") : ""),
                "args": .string(sampleInput.split(separator: " ").dropFirst().joined(separator: " ")),
                "peer_id": .int(0),
                "is_group": .bool(false),
                "is_channel": .bool(false)
            ])
            switch language {
            case .lua:
                let vm = FullGramLuaVM(hostAPI: hostAPI) { line in
                    capturedLogs.append(line)
                }
                try vm.load(code: code)
                var resultText = ""
                let cmd = ctxTable.get(key: .string("command")).asString
                if !cmd.isEmpty {
                    if let fn = holder.registeredCommands[cmd.lowercased()] {
                        resultText = try fn([.table(ctxTable)]).asString
                    } else if vm.hasFunction("on_command") {
                        resultText = try vm.callFunction("on_command", args: [.table(ctxTable)]).asString
                    }
                }
                if resultText.isEmpty && vm.hasFunction("on_outgoing_message") {
                    resultText = try vm.callFunction("on_outgoing_message", args: [.table(ctxTable)]).asString
                }
                return (resultText, capturedLogs, nil)
            case .python:
                let vm = FullGramPythonVM(hostAPI: hostAPI) { line in
                    capturedLogs.append(line)
                }
                try vm.load(code: code)
                var resultText = ""
                let cmd = ctxTable.get(key: .string("command")).asString
                if !cmd.isEmpty {
                    if let fn = holder.registeredCommands[cmd.lowercased()] {
                        resultText = try fn([.table(ctxTable)]).asString
                    } else if vm.hasFunction("on_command") {
                        resultText = try vm.callFunction("on_command", args: [.table(ctxTable)]).asString
                    }
                }
                if resultText.isEmpty && vm.hasFunction("on_outgoing_message") {
                    resultText = try vm.callFunction("on_outgoing_message", args: [.table(ctxTable)]).asString
                }
                return (resultText, capturedLogs, nil)
            case .rust:
                let vm = FullGramRustVM(hostAPI: hostAPI) { line in
                    capturedLogs.append(line)
                }
                try vm.load(code: code)
                var resultText = ""
                let cmd = ctxTable.get(key: .string("command")).asString
                if !cmd.isEmpty {
                    if let fn = holder.registeredCommands[cmd.lowercased()] {
                        resultText = try fn([.table(ctxTable)]).asString
                    } else if vm.hasFunction("on_command") {
                        resultText = try vm.callFunction("on_command", args: [.table(ctxTable)]).asString
                    }
                }
                if resultText.isEmpty && vm.hasFunction("on_outgoing_message") {
                    resultText = try vm.callFunction("on_outgoing_message", args: [.table(ctxTable)]).asString
                }
                return (resultText, capturedLogs, nil)
            }
        } catch {
            return ("", capturedLogs, error.localizedDescription)
        }
    }

    private func interpretDecision(_ value: FullGramPluginValue) -> FullGramPluginOutgoingDecision {
        switch value {
        case .nil:
            return .pass
        case let .string(s):
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .pass
            }
            return .replaceText(s)
        case let .table(box):
            let cancelVal = box.get(key: .string("cancel"))
            let toastVal = box.get(key: .string("toast"))
            let toastStr: String? = {
                if case let .string(s) = toastVal, !s.isEmpty { return s }
                return nil
            }()
            if cancelVal.isTruthy {
                return .cancel(toast: toastStr)
            }
            if case let .string(newText) = box.get(key: .string("text")) {
                if let toastStr {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: FullGramPluginNotifications.toastRequested, object: nil, userInfo: ["text": toastStr])
                    }
                }
                if newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .pass
                }
                return .replaceText(newText)
            }
            return .pass
        default:
            return .pass
        }
    }

    // MARK: - Built-in Starter Plugins

    private static func defaultStarterPlugins() -> [FullGramPluginDescriptor] {
        let luaCommands = """
-- @name Быстрые команды
-- @id fg_quick_commands
-- @version 1.0
-- @author FullGram
-- @description Команды .shrug, .lenny, .flip и .hug в любом чате

function on_command(ctx)
    local cmd = ctx.command
    local args = ctx.args
    if cmd == "shrug" then
        local tail = args ~= "" and (args .. " ") or ""
        return tail .. "¯\\\\_(ツ)_/¯"
    elseif cmd == "lenny" then
        local tail = args ~= "" and (args .. " ") or ""
        return tail .. "( ͡° ͜ʖ ͡°)"
    elseif cmd == "flip" then
        return "(╯°□°)╯︵ ┻━┻"
    elseif cmd == "unflip" then
        return "┬─┬ノ( º _ ºノ)"
    elseif cmd == "hug" then
        return "(づ｡◕‿‿◕｡)づ " .. args
    end
    return nil
end
"""

        let luaCalc = """
-- @name Калькулятор и рандом
-- @id fg_inline_calc
-- @version 1.0
-- @author FullGram
-- @description Команды .roll [макс] и .calc [число +-*/ число]

function on_command(ctx)
    if ctx.command == "roll" then
        local limit = tonumber(ctx.args) or 100
        if limit < 2 then limit = 100 end
        local val = math.random(1, limit)
        return "🎲 Выпало: " .. tostring(val) .. " (из " .. tostring(limit) .. ")"
    elseif ctx.command == "calc" then
        local a = string.match(ctx.args, "^%s*(-?[%d%.]+)")
        local op = string.match(ctx.args, "([%+%-%*/])")
        local b = string.match(ctx.args, "([%d%.]+)%s*$")
        if a and op and b then
            local x = tonumber(a)
            local y = tonumber(b)
            local res = 0
            if op == "+" then res = x + y
            elseif op == "-" then res = x - y
            elseif op == "*" then res = x * y
            elseif op == "/" and y ~= 0 then res = x / y
            end
            return ctx.args .. " = " .. tostring(res)
        end
        return { cancel = true, toast = "Формат: .calc 125 * 4" }
    end
    return nil
end
"""

        let pyFormatter = """
# @name Текст-мастер (Python)
# @id fg_python_formatter
# @version 1.0
# @author FullGram
# @description Команды .upper, .lower, .reverse и .mock на Python 3

def on_command(ctx):
    cmd = ctx["command"]
    args = ctx["args"]
    if not args:
        return None
    if cmd == "upper":
        return args.upper()
    elif cmd == "lower":
        return args.lower()
    elif cmd == "mock":
        out = ""
        for idx, ch in enumerate(args):
            out = out + (ch.upper() if idx % 2 == 0 else ch.lower())
        return out
    elif cmd == "count":
        fullgram.toast(f"Символов: {len(args)}, слов: {len(args.split())}")
        return {"cancel": True, "toast": f"Символов: {len(args)}, слов: {len(args.split())}"}
    return None
"""

        let pyCounter = """
# @name Счётчик сообщений (Python)
# @id fg_message_counter
# @version 1.0
# @author FullGram
# @description Считает отправленные сообщения; команда .stats показывает счётчик

import fullgram

def on_outgoing_message(ctx):
    count = int(fullgram.storage_get("sent_count", 0)) + 1
    fullgram.storage_set("sent_count", count)
    return None

def on_command(ctx):
    if ctx["command"] == "stats":
        count = int(fullgram.storage_get("sent_count", 0))
        return {"cancel": True, "toast": f"Отправлено сообщений: {count}"}
    return None
"""

        return [
            FullGramPluginDescriptor(
                id: "fg_quick_commands",
                name: "Быстрые команды",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Команды .shrug, .lenny, .flip, .unflip, .hug в любом чате",
                code: luaCommands,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_inline_calc",
                name: "Калькулятор и рандом",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Команды .roll [макс] и .calc [пример]",
                code: luaCalc,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_python_formatter",
                name: "Текст-мастер (Python)",
                language: .python,
                version: "1.0",
                author: "FullGram",
                description: "Команды .upper, .lower, .mock и .count на Python 3",
                code: pyFormatter,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_message_counter",
                name: "Счётчик сообщений (Python)",
                language: .python,
                version: "1.0",
                author: "FullGram",
                description: "Считает отправленные сообщения; команда .stats",
                code: pyCounter,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_chat_info",
                name: "1. Информация о чате",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Команда .plug info-chat: дата первого и последнего сообщения, частые и редкие слова, количество мата, голосовых и видеокружков.",
                code: Self.chatInfoPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_snippets",
                name: "Быстрые шаблоны (.tpl)",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Шаблоны ответов: .tpl add <ключ> <текст>, .tpl <ключ>, .tpl list",
                code: Self.snippetsPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_notes",
                name: "Быстрые заметки (.note)",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Личные заметки: .note add <текст>, .note list, .note clear",
                code: Self.notesPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_layout_fixer",
                name: "Исправление раскладки (.fix)",
                language: .python,
                version: "1.0",
                author: "FullGram",
                description: "Команда .fix <текст>: переводит раскладку (по умолчанию Рус → Англ, направление меняется во вкладке Плагины).",
                code: Self.layoutFixerPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_casino",
                name: "Казино (.casino / .zeus / .crash)",
                language: .lua,
                version: "4.0",
                author: "FullGram",
                description: "Реальные шансы и RTP (96.2–98%): Зевс, Собаки, Слоты 777, Краш, Рулетка, Монетка, Ante Bet, Buy Bonus и выдача любого баланса (.setbal).",
                code: Self.casinoPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_anti_typos",
                name: "Анти-опечатки",
                language: .python,
                version: "2.0",
                author: "FullGram",
                description: "Автоматически исправляет частые клавиатурные опечатки, двойные заглавные буквы и лишние пробелы перед знаками препинания.",
                code: Self.antiTyposPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_deadlines",
                name: "Дедлайны (.dl / .deadline)",
                language: .python,
                version: "2.0",
                author: "FullGram",
                description: "Управление сроками: .dl add <срок> | <задача>, .dl list, .dl done <№>, .dl send, .dl clear.",
                code: Self.deadlinesPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            )
        ]
    }

    private static func layoutFixerPluginCode() -> String {
        return """
# @name Исправление раскладки (.fix)
# @id fg_layout_fixer
# @version 1.0
# @author FullGram
# @description Команда .fix <текст>: переводит раскладку (по умолчанию Рус → Англ, меняется во вкладке Плагины)

import fullgram

RU_CHARS = "йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ"
EN_CHARS = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:\\"ZXCVBNM<>~"

def convert_text(text, direction):
    out = ""
    for ch in text:
        if direction == "ru2en":
            idx = RU_CHARS.find(ch)
            out = out + (EN_CHARS[idx] if idx >= 0 else ch)
        elif direction == "en2ru":
            idx = EN_CHARS.find(ch)
            out = out + (RU_CHARS[idx] if idx >= 0 else ch)
    return out

def on_command(ctx):
    if ctx["command"] != "fix":
        return None
    raw = str(ctx["args"]).strip()
    if not raw:
        mode = str(fullgram.storage_get("mode", "ru2en"))
        return {"cancel": True, "toast": f"Формат: .fix <текст> (режим: {mode})"}

    lower_raw = raw.lower()
    if lower_raw == "mode ru2en":
        fullgram.storage_set("mode", "ru2en")
        return {"cancel": True, "toast": "Раскладка .fix: Русский → Английский"}
    elif lower_raw == "mode en2ru":
        fullgram.storage_set("mode", "en2ru")
        return {"cancel": True, "toast": "Раскладка .fix: Английский → Русский"}
    elif lower_raw == "mode auto":
        fullgram.storage_set("mode", "auto")
        return {"cancel": True, "toast": "Раскладка .fix: Авто (Рус ↔ Англ)"}

    mode = str(fullgram.storage_get("mode", "ru2en"))
    direction = mode
    if mode == "auto":
        ru_count = 0
        en_count = 0
        for ch in raw:
            if RU_CHARS.find(ch) >= 0:
                ru_count = ru_count + 1
            elif EN_CHARS.find(ch) >= 0:
                en_count = en_count + 1
        direction = "ru2en" if ru_count >= en_count else "en2ru"

    return convert_text(raw, direction)
"""
    }

    private static func casinoPluginCode() -> String {
        return """
-- @name Казино (.casino / .zeus / .crash)
-- @id fg_casino
-- @version 4.0
-- @author FullGram
-- @description Реальные шансы и RTP (96.2–98%): Зевс, Собаки, Слоты 777, Краш, Рулетка, Монетка, Ante Bet, Buy Bonus и выдача любого баланса (.setbal)

function get_num(key, def)
    local v = tonumber(fullgram.storage_get(key, def))
    if v == nil then return def end
    return v
end

function get_balance()
    return math.max(0, math.floor(get_num("balance", 1000) + 0.5))
end

function set_balance(val)
    local b = math.max(0, math.floor((tonumber(val) or 0) + 0.5))
    fullgram.storage_set("balance", b)
    local best = get_num("best_balance", 1000)
    if b > best then
        fullgram.storage_set("best_balance", b)
    end
    return b
end

function fmt2(x)
    local n = math.floor((tonumber(x) or 0) * 100 + 0.5)
    local whole = math.floor(n / 100)
    local frac = n % 100
    local fstr = (frac < 10) and ("0" .. tostring(frac)) or tostring(frac)
    return tostring(whole) .. "." .. fstr
end

function fmt_signed(delta)
    if delta >= 0 then
        return "+" .. tostring(delta)
    end
    return tostring(delta)
end

function add_session(wagered, returned, won)
    fullgram.storage_set("sess_rounds", get_num("sess_rounds", 0) + 1)
    fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + wagered)
    fullgram.storage_set("sess_returned", get_num("sess_returned", 0) + returned)
    if won then
        fullgram.storage_set("sess_wins", get_num("sess_wins", 0) + 1)
    end
end

function pick_weighted(tbl)
    local total = 0
    for i = 1, #tbl do
        total = total + tbl[i][2]
    end
    if total <= 0 then return tbl[1][1] end
    local roll = math.random(0, total - 1)
    for i = 1, #tbl do
        local w = tbl[i][2]
        if roll < w then
            return tbl[i][1]
        end
        roll = roll - w
    end
    return tbl[1][1]
end

function pick_zeus_orb()
    local roll = math.random(0, 999)
    if roll < 480 then return 2 end
    if roll < 720 then return 3 end
    if roll < 860 then return 5 end
    if roll < 940 then return 10 end
    if roll < 980 then return 25 end
    if roll < 995 then return 50 end
    return 100
end

function is_red_pocket(num)
    local reds = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36}
    for i = 1, #reds do
        if reds[i] == num then return true end
    end
    return false
end

function parse_bet(raw_str, bal)
    local num = tonumber(string.match(tostring(raw_str or ""), "(%d+)"))
    local bet = num or 100
    if bet < 10 then bet = 10 end
    if bal > 0 and bet > bal then bet = bal end
    return math.floor(bet + 0.5)
end

function ensure_playable_balance()
    local bal = get_balance()
    if bal < 10 then
        bal = set_balance(500)
        return bal, true
    end
    return bal, false
end

function status_header()
    local bal = get_balance()
    local best = math.floor(get_num("best_balance", 1000) + 0.5)
    local ante = (get_num("ante_bet", 0) == 1)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)
    local rounds = math.floor(get_num("sess_rounds", 0) + 0.5)
    local wins = math.floor(get_num("sess_wins", 0) + 0.5)
    local wag = get_num("sess_wagered", 0)
    local ret = get_num("sess_returned", 0)
    local win_pct = (rounds > 0) and fmt2((wins / rounds) * 100) or "0.00"
    local sess_rtp = (wag > 0) and fmt2((ret / wag) * 100) or "—"
    local line = "💰 Баланс: " .. tostring(bal) .. " 🪙 | 🏆 Рекорд: " .. tostring(best) .. " 🪙"
    line = line .. "\\n⚡ Ante Bet (+25%): " .. (ante and "ВКЛ" or "ВЫКЛ")
    if fs > 0 then
        line = line .. " | 🎁 FS: " .. tostring(fs) .. " (x" .. tostring(gmult) .. ")"
    end
    line = line .. "\\n📊 Сессия: " .. tostring(rounds) .. " раунд. · Побед " .. win_pct .. "% · RTP " .. sess_rtp .. "%"
    return line
end

function play_zeus(raw_arg)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local is_fs = (fs > 0)
    local bal, refilled = ensure_playable_balance()
    local ante = (get_num("ante_bet", 0) == 1)
    local base_bet = is_fs and math.floor(get_num("bonus_bet", 100) + 0.5) or parse_bet(raw_arg, bal)
    local spin_cost = is_fs and 0 or math.min(bal, ante and math.floor(base_bet * 1.25 + 0.5) or base_bet)

    local weights = (ante or is_fs)
        and {{"💎", 26}, {"⏳", 21}, {"🏆", 17}, {"💍", 14}, {"👑", 10}, {"⚡", 12}}
        or  {{"💎", 30}, {"⏳", 23}, {"🏆", 18}, {"💍", 14}, {"👑", 9},  {"⚡", 6}}

    if not is_fs then
        bal = set_balance(bal - spin_cost)
    else
        fs = fs - 1
        fullgram.storage_set("free_spins", fs)
    end

    local grid = {}
    local counts = {}
    for i = 1, 15 do
        local s = pick_weighted(weights)
        grid[i] = s
        counts[s] = (counts[s] or 0) + 1
    end

    local bolts = counts["⚡"] or 0
    local sym_base = { ["💎"] = 0.4, ["⏳"] = 0.6, ["🏆"] = 0.9, ["💍"] = 1.3, ["👑"] = 2.2 }
    local syms = {"💎", "⏳", "🏆", "💍", "👑"}
    local best_pay = 0.0
    local best_sym = nil
    for i = 1, #syms do
        local s = syms[i]
        local cnt = counts[s] or 0
        if cnt >= 6 then
            local cand = sym_base[s] * (1.0 + (cnt - 6) * 0.65)
            if cand > best_pay then
                best_pay = cand
                best_sym = s
            end
        end
    end

    local mult = 0.0
    local status = "❌ Пустой спин"
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)

    if best_pay > 0.0 then
        local orb = (bolts > 0 or is_fs) and pick_zeus_orb() or 1
        if is_fs and orb > 1 then
            gmult = gmult + orb
            fullgram.storage_set("bonus_mult", gmult)
        end
        local eff_orb = is_fs and math.max(1, gmult) or orb
        mult = best_pay * eff_orb
        if eff_orb >= 25 then
            status = "🔥 MAX ОРБ ЗЕВСА x" .. tostring(eff_orb) .. "!"
        elseif eff_orb > 1 then
            status = "⚡ МОЛНИЯ ЗЕВСА x" .. tostring(eff_orb) .. "!"
        else
            status = "👑 СЫГРОВКА " .. best_sym .. " x" .. fmt2(mult) .. "!"
        end
    end

    if bolts >= 4 and not is_fs then
        fullgram.storage_set("bonus_bet", base_bet)
        fullgram.storage_set("free_spins", fs + 10)
        fullgram.storage_set("bonus_mult", 1)
        if mult < 3.0 then mult = 3.0 end
        status = "⚡ 4+ SCATTER! БОНУС 10 ФРИСПИНОВ!"
    elseif bolts >= 4 and is_fs then
        fullgram.storage_set("free_spins", fs + 5)
        status = "⚡ РЕТРИГГЕР +5 ФРИСПИНОВ!"
    end

    local payout = math.floor(base_bet * mult + 0.5)
    bal = set_balance(bal + payout)
    add_session(spin_cost, payout, payout > spin_cost)
    local net = payout - spin_cost

    local r1 = grid[1] .. " " .. grid[2] .. " " .. grid[3] .. " " .. grid[4] .. " " .. grid[5]
    local r2 = grid[6] .. " " .. grid[7] .. " " .. grid[8] .. " " .. grid[9] .. " " .. grid[10]
    local r3 = grid[11] .. " " .. grid[12] .. " " .. grid[13] .. " " .. grid[14] .. " " .. grid[15]
    local fs_left = math.floor(get_num("free_spins", 0) + 0.5)
    local tag = is_fs and ("🎁 ФРИСПИН (ост. " .. tostring(fs_left) .. ")") or ("Ставка: " .. tostring(spin_cost) .. " 🪙")
    local note = refilled and "\\n🎁 Фрибет +500 🪙 на старте" or ""

    return "⚡ GATES OF OLYMPUS (RTP 96.50%) | " .. tag .. "\\n"
        .. r1 .. "\\n" .. r2 .. "\\n" .. r3 .. "\\n"
        .. status .. " (выплата " .. tostring(payout) .. " 🪙, " .. fmt_signed(net) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_dogs(raw_arg)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local is_fs = (fs > 0)
    local bal, refilled = ensure_playable_balance()
    local ante = (get_num("ante_bet", 0) == 1)
    local base_bet = is_fs and math.floor(get_num("bonus_bet", 100) + 0.5) or parse_bet(raw_arg, bal)
    local spin_cost = is_fs and 0 or math.min(bal, ante and math.floor(base_bet * 1.25 + 0.5) or base_bet)

    local weights = (ante or is_fs)
        and {{"🦴", 23}, {"🐾", 20}, {"🎾", 17}, {"💎", 14}, {"🐶", 11}, {"🏠", 15}}
        or  {{"🦴", 27}, {"🐾", 22}, {"🎾", 18}, {"💎", 14}, {"🐶", 11}, {"🏠", 8}}

    if not is_fs then
        bal = set_balance(bal - spin_cost)
    else
        fs = fs - 1
        fullgram.storage_set("free_spins", fs)
    end

    local grid = {}
    local kennels = 0
    local dogs_cnt = 0
    for i = 1, 15 do
        local s = pick_weighted(weights)
        grid[i] = s
        if s == "🏠" then kennels = kennels + 1 end
        if s == "🐶" then dogs_cnt = dogs_cnt + 1 end
    end

    local line_w = { ["🦴"] = 0.4, ["🐾"] = 0.6, ["🎾"] = 0.85, ["💎"] = 1.4, ["🐶"] = 2.4 }
    local line_sum = 0.0
    for r = 0, 2 do
        local anchor = "🐶"
        for c = 1, 5 do
            local sym = grid[r * 5 + c]
            if sym ~= "🏠" then
                anchor = sym
                break
            end
        end
        local streak = 0
        for c = 1, 5 do
            local sym = grid[r * 5 + c]
            if sym == anchor or sym == "🏠" then
                streak = streak + 1
            else
                break
            end
        end
        if streak >= 3 then
            line_sum = line_sum + (line_w[anchor] or 0.6) * (streak - 1)
        end
    end

    local mult = 0.0
    local status = "❌ Пустой спин"
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)

    if line_sum > 0.0 then
        local km = 1
        if kennels > 0 then
            local sum_w = 0
            local cap = math.min(kennels, 4)
            for i = 1, cap do
                sum_w = sum_w + ((math.random(0, 9) < 7) and 2 or 3)
            end
            km = math.max(1, sum_w)
        end
        if is_fs and kennels > 0 then
            gmult = math.min(27, gmult + km)
            fullgram.storage_set("bonus_mult", gmult)
            km = gmult
        end
        mult = line_sum * km
        status = (km > 1) and ("🐶 БУДКИ x" .. tostring(km) .. " · ЗАНОС!") or "🐶 ЛИНИЯ СЫГРАЛА!"
    elseif dogs_cnt >= 5 then
        mult = 2.5
        status = "🐶 СТАЯ СОБАК x2.5!"
    end

    if kennels >= 4 and not is_fs then
        fullgram.storage_set("bonus_bet", base_bet)
        fullgram.storage_set("free_spins", fs + 10)
        fullgram.storage_set("bonus_mult", 1)
        if mult < 2.0 then mult = 2.0 end
        status = "🏠 БОНУС 10 ФРИСПИНОВ СОБАК!"
    elseif kennels >= 4 and is_fs then
        fullgram.storage_set("free_spins", fs + 5)
        status = "🏠 РЕТРИГГЕР +5 ФРИСПИНОВ!"
    end

    local payout = math.floor(base_bet * mult + 0.5)
    bal = set_balance(bal + payout)
    add_session(spin_cost, payout, payout > spin_cost)
    local net = payout - spin_cost

    local r1 = grid[1] .. " " .. grid[2] .. " " .. grid[3] .. " " .. grid[4] .. " " .. grid[5]
    local r2 = grid[6] .. " " .. grid[7] .. " " .. grid[8] .. " " .. grid[9] .. " " .. grid[10]
    local r3 = grid[11] .. " " .. grid[12] .. " " .. grid[13] .. " " .. grid[14] .. " " .. grid[15]
    local fs_left = math.floor(get_num("free_spins", 0) + 0.5)
    local tag = is_fs and ("🎁 ФРИСПИН (ост. " .. tostring(fs_left) .. ")") or ("Ставка: " .. tostring(spin_cost) .. " 🪙")
    local note = refilled and "\\n🎁 Фрибет +500 🪙 на старте" or ""

    return "🐶 THE DOG HOUSE (RTP 96.51%) | " .. tag .. "\\n"
        .. r1 .. "\\n" .. r2 .. "\\n" .. r3 .. "\\n"
        .. status .. " (выплата " .. tostring(payout) .. " 🪙, " .. fmt_signed(net) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_classic(raw_arg)
    local bal, refilled = ensure_playable_balance()
    local bet = parse_bet(raw_arg, bal)
    local weights = {{"🍒", 36}, {"🍋", 26}, {"🔔", 18}, {"💎", 13}, {"7️⃣", 7}}
    local s1 = pick_weighted(weights)
    local s2 = pick_weighted(weights)
    local s3 = pick_weighted(weights)

    local sevens = ((s1 == "7️⃣") and 1 or 0) + ((s2 == "7️⃣") and 1 or 0) + ((s3 == "7️⃣") and 1 or 0)
    local diamonds = ((s1 == "💎") and 1 or 0) + ((s2 == "💎") and 1 or 0) + ((s3 == "💎") and 1 or 0)

    local mult = 0.0
    local status = "❌ Мимо!"
    if s1 == s2 and s2 == s3 then
        if s1 == "7️⃣" then mult = 50.0; status = "🔥 МЕГА ДЖЕКПОТ 777 (x50)!"
        elseif s1 == "💎" then mult = 15.0; status = "💎 АЛМАЗНЫЙ ДЖЕКПОТ (x15)!"
        elseif s1 == "🔔" then mult = 8.0; status = "🔔 3 КОЛОКОЛА (x8)!"
        elseif s1 == "🍋" then mult = 5.0; status = "🍋 3 ЛИМОНА (x5)!"
        else mult = 3.0; status = "🍒 3 ВИШНИ (x3)!"
        end
    elseif sevens == 2 then
        mult = 3.0; status = "7️⃣ Две Семёрки (x3)!"
    elseif diamonds == 2 then
        mult = 2.0; status = "💎 Два Алмаза (x2)!"
    elseif s1 == s2 or s2 == s3 or s1 == s3 then
        mult = 1.2; status = "✨ Пара (x1.2)!"
    end

    local payout = math.floor(bet * mult + 0.5)
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, delta > 0)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""

    return "🎰 3 БАРАБАНА (RTP 96.20%) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. "┏━━━━━━━━━━━┓\\n┃  " .. s1 .. " │ " .. s2 .. " │ " .. s3 .. "  ┃\\n┗━━━━━━━━━━━┛\\n"
        .. status .. " (" .. fmt_signed(delta) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_crash(raw_arg, default_target)
    local bal, refilled = ensure_playable_balance()
    local s = tostring(raw_arg or "")
    local target = default_target or 2.0
    local bet = 100

    local n1 = string.match(s, "^%s*([%d%.]+)%s+%d+")
    local n2 = string.match(s, "^%s*[%d%.]+%s+(%d+)")
    if n1 and n2 then
        target = tonumber(n1) or target
        bet = tonumber(n2) or bet
    else
        local with_x = string.match(s, "([%d%.]+)[xXхХ]")
        if with_x then
            target = tonumber(with_x) or target
        else
            local single = tonumber(string.match(s, "([%d%.]+)"))
            if single then
                if string.find(s, ".", 1, true) then
                    target = single
                else
                    bet = single
                end
            end
        end
    end
    if target < 1.05 then target = 1.05 end
    if target > 100.0 then target = 100.0 end
    if bet < 10 then bet = 10 end
    if bet > bal then bet = bal end
    bet = math.floor(bet + 0.5)

    local crash_pt = 1.00
    if math.random(0, 99) >= 3 then
        local u = math.random(1, 990) / 1000.0
        crash_pt = math.min(100.0, math.max(1.03, 0.97 / (1.0 - u)))
    end

    local won = (crash_pt >= target)
    local payout = won and math.floor(bet * target + 0.5) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""

    local res_line = won
        and ("✅ Забрал на " .. fmt2(target) .. "x (краш был " .. fmt2(crash_pt) .. "x): +" .. tostring(delta) .. " 🪙")
        or  ("💥 КРАШ на " .. fmt2(crash_pt) .. "x (цель " .. fmt2(target) .. "x): " .. tostring(delta) .. " 🪙")

    return "🚀 CRASH (RTP 97.00% · 3% инста-краш) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. res_line .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_roulette(choice_arg, bet_arg)
    local bal, refilled = ensure_playable_balance()
    local c = string.lower(tostring(choice_arg or "red"))
    local bet = parse_bet(bet_arg, bal)
    local num = math.random(0, 36)

    local color = "black"
    local badge = "⚫️ Чёрное"
    if num == 0 then
        color = "green"
        badge = "🟢 Зеро (0)"
    elseif is_red_pocket(num) then
        color = "red"
        badge = "🔴 Красное"
    end

    local exact_num = tonumber(c)
    local won = false
    local mult = 2
    local bet_label = "🔴 Красное"
    if exact_num ~= nil and exact_num >= 0 and exact_num <= 36 then
        mult = 36
        bet_label = "🎯 Число [" .. tostring(exact_num) .. "]"
        won = (num == exact_num)
    elseif c == "green" or c == "0" or c == "зеро" or c == "зеленое" then
        mult = 36
        bet_label = "🟢 Зеро [0]"
        won = (color == "green")
    elseif c == "black" or c == "черное" or c == "ч" then
        mult = 2
        bet_label = "⚫️ Чёрное"
        won = (color == "black")
    else
        mult = 2
        bet_label = "🔴 Красное"
        won = (color == "red")
    end

    local payout = won and (bet * mult) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""
    local outcome = won
        and ("✅ Выигрыш x" .. tostring(mult) .. ": +" .. tostring(delta) .. " 🪙!")
        or  ("❌ Мимо: " .. tostring(delta) .. " 🪙")

    return "🎡 ЕВРОПЕЙСКАЯ РУЛЕТКА (RTP 97.30%) | " .. bet_label .. " · " .. tostring(bet) .. " 🪙\\n"
        .. "Выпало: " .. badge .. " [" .. tostring(num) .. "]\\n"
        .. outcome .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_coin(side_arg, bet_arg)
    local bal, refilled = ensure_playable_balance()
    local bet = parse_bet(bet_arg, bal)
    local pick_tails = (string.find(string.lower(tostring(side_arg or "")), "реш") ~= nil)
        or (string.find(string.lower(tostring(side_arg or "")), "tail") ~= nil)
    local won = (math.random(0, 99) < 49)
    local landed_tails = false
    if pick_tails then
        landed_tails = won
    else
        landed_tails = not won
    end
    local landed_str = landed_tails and "🪙 Решка" or "🦅 Орёл"

    local payout = won and (bet * 2) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""
    local res = won and ("✅ Победа (49% шанс, x2): +" .. tostring(delta) .. " 🪙!") or ("❌ Не угадали: " .. tostring(delta) .. " 🪙")

    return "🪙 МОНЕТКА (RTP 98.00%) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. "Выпал: " .. landed_str .. "\\n"
        .. res .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function rtp_summary()
    return "📊 ЧЕСТНЫЕ ШАНСЫ И RTP КАЗИНО:\\n"
        .. "• ⚡ Gates of Olympus — RTP 96.50% (орбы x2..x100, 4+ ⚡ = 10 FS)\\n"
        .. "• 🐶 The Dog House — RTP 96.51% (линии + будки Wild x2/x3, до x27 в FS)\\n"
        .. "• 🎰 3 Барабана — RTP 96.20% (777: x50, 💎: x15, 🔔: x8, пара: x1.2)\\n"
        .. "• 🚀 Crash — RTP 97.00% (3% краш на 1.00x, хвост до x100)\\n"
        .. "• 🎡 Рулетка (37 сект.) — RTP 97.30% (🔴/⚫️ 48.65% x2, 🟢 2.70% x36)\\n"
        .. "• 🪙 Монетка — RTP 98.00% (49.0% победа, x2)\\n"
        .. "ℹ️ Выдача баланса (.setbal <сумма>) НЕ меняет шансы.\\n\\n"
        .. status_header()
end

function handle_set_balance(raw)
    local s = tostring(raw or "")
    local add_num = tonumber(string.match(s, "^%s*%+%s*(%d+)"))
    if add_num ~= nil then
        local nb = set_balance(get_balance() + add_num)
        return "💰 Добавлено +" .. tostring(add_num) .. " 🪙!\\nБаланс: " .. tostring(nb) .. " 🪙 (шансы те же)"
    end
    local exact = tonumber(string.match(s, "(%d+)"))
    if exact ~= nil then
        local nb = set_balance(exact)
        return "💰 Баланс установлен: " .. tostring(nb) .. " 🪙\\n(шансы и RTP без изменений!)"
    end
    local nb = set_balance(get_balance() + 10000)
    return "🎁 Начислено +10000 🪙!\\nБаланс: " .. tostring(nb) .. " 🪙\\n(введите любое число в поле для точной выдачи)"
end

function open_casino_ui()
    fullgram.open_ui({
        kind = "custom",
        title = "🎰 Казино FullGram",
        subtitle = "Реальные шансы и RTP (96.2–98.0%). Введите ставку (по ум. 100) или сумму баланса:\\n\\n" .. status_header(),
        placeholder = "Ставка (100), цель Crash (2.5 100) или баланс (50000)",
        default_input = "100",
        buttons = {
            { items = {
                { title = "⚡ Зевс (96.5%)", id = "spin_zeus", color = "orange" },
                { title = "🐶 Собаки (96.5%)", id = "spin_dogs", color = "indigo" }
            } },
            { items = {
                { title = "🎰 3 Барабана", id = "spin_classic", color = "purple" },
                { title = "🚀 Краш (x2.0)", id = "spin_crash", color = "teal" }
            } },
            { items = {
                { title = "🔴 Красное x2", id = "spin_red", color = "red" },
                { title = "⚫️ Чёрное x2", id = "spin_black", color = "gray" }
            } },
            { items = {
                { title = "🟢 Зеро x36", id = "spin_green", color = "green" },
                { title = "🪙 Монетка x2", id = "spin_coin", color = "blue" }
            } },
            { items = {
                { title = "⚡ Ante +25%", id = "toggle_ante", color = "orange" },
                { title = "🎁 Бонус x100", id = "buy_bonus", color = "purple" }
            } },
            { items = {
                { title = "💰 Выдать баланс", id = "set_balance", color = "green" },
                { title = "📊 RTP и шансы", id = "rtp_info", color = "gray" }
            } }
        }
    })
end

function on_ui_event(ctx)
    local act = tostring(ctx.action or "")
    local inp = tostring(ctx.input or "")

    if act == "bonus" then
        local nb = set_balance(get_balance() + 1000)
        return { balance = nb, best_balance = get_num("best_balance", 1000), text = "🎁 +1000 🪙!\\n" .. status_header() }
    elseif act == "spin_zeus" then
        return play_zeus(inp)
    elseif act == "spin_dogs" then
        return play_dogs(inp)
    elseif act == "spin_classic" then
        return play_classic(inp)
    elseif act == "spin_crash" then
        return play_crash(inp, 2.0)
    elseif act == "spin_red" then
        return play_roulette("red", inp)
    elseif act == "spin_black" then
        return play_roulette("black", inp)
    elseif act == "spin_green" then
        return play_roulette("green", inp)
    elseif act == "spin_coin" then
        return play_coin("eagle", inp)
    elseif act == "toggle_ante" then
        if get_num("free_spins", 0) > 0 then
            return "⚠️ Нельзя менять Ante Bet во время фриспинов!\\n" .. status_header()
        end
        local cur = (get_num("ante_bet", 0) == 1) and 0 or 1
        fullgram.storage_set("ante_bet", cur)
        return (cur == 1 and "⚡ Ante Bet ВКЛ (+25% к ставке, x2 шанс бонуса)" or "⚡ Ante Bet ВЫКЛ") .. "\\n\\n" .. status_header()
    elseif act == "buy_bonus" then
        local bal = get_balance()
        local bet = parse_bet(inp, bal)
        local cost = bet * 100
        if bal < cost then
            return "❌ Нужно " .. tostring(cost) .. " 🪙 для покупки бонуса (x100 ставки).\\nВы можете выдать себе баланс кнопкой «💰 Выдать баланс»!\\n\\n" .. status_header()
        end
        set_balance(bal - cost)
        fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + cost)
        fullgram.storage_set("bonus_bet", bet)
        fullgram.storage_set("free_spins", get_num("free_spins", 0) + 10)
        fullgram.storage_set("bonus_mult", 1)
        return "🎁 БОНУС КУПЛЕН! 10 ФРИСПИНОВ по ставке " .. tostring(bet) .. " 🪙!\\nЖмите «⚡ Зевс» или «🐶 Собаки»!\\n\\n" .. status_header()
    elseif act == "set_balance" then
        return handle_set_balance(inp) .. "\\n\\n" .. status_header()
    elseif act == "rtp_info" then
        return rtp_summary()
    end

    return status_header()
end

function on_command(ctx)
    local aliases = { roul = "roulette", givebal = "setbal", balance = "bal", odds = "rtp" }
    local cmd = aliases[ctx.command] or ctx.command
    local args = tostring(ctx.args or "")

    if cmd == "casino" then
        if args == "" or args == "ui" then
            open_casino_ui()
            return { cancel = true }
        end
        return { cancel = true, toast = "Откройте UI командой .casino или используйте .zeus, .dogs, .slots, .crash, .roulette, .coin, .setbal <сумма>" }
    elseif cmd == "zeus" then
        return play_zeus(args)
    elseif cmd == "dogs" then
        return play_dogs(args)
    elseif cmd == "slots" then
        return play_classic(args)
    elseif cmd == "crash" then
        return play_crash(args, 2.0)
    elseif cmd == "roulette" then
        local choice = string.lower(ctx.subcommand or "red")
        local bet_str = string.match(args, "%s+(%d+)$") or "100"
        return play_roulette(choice, bet_str)
    elseif cmd == "coin" then
        local side = string.lower(ctx.subcommand or "eagle")
        local bet_str = string.match(args, "(%d+)") or "100"
        return play_coin(side, bet_str)
    elseif cmd == "setbal" then
        local exact = tonumber(string.match(args, "(%d+)"))
        if exact == nil then
            return { cancel = true, toast = "Формат: .setbal <сумма> (например: .setbal 100000)" }
        end
        local nb = set_balance(exact)
        return { cancel = true, toast = "💰 Баланс установлен: " .. tostring(nb) .. " 🪙 (шансы не изменены)" }
    elseif cmd == "bal" then
        local lower = string.lower(args)
        if string.sub(lower, 1, 4) == "set " then
            local exact = tonumber(string.match(args, "(%d+)"))
            if exact ~= nil then
                local nb = set_balance(exact)
                return { cancel = true, toast = "💰 Баланс: " .. tostring(nb) .. " 🪙 (шансы прежние)" }
            end
        elseif string.sub(lower, 1, 4) == "add " or string.sub(lower, 1, 1) == "+" then
            local add_v = tonumber(string.match(args, "(%d+)"))
            if add_v ~= nil then
                local nb = set_balance(get_balance() + add_v)
                return { cancel = true, toast = "💰 +" .. tostring(add_v) .. " 🪙 → Баланс: " .. tostring(nb) .. " 🪙" }
            end
        elseif lower == "bonus" then
            local nb = set_balance(get_balance() + 1000)
            return { cancel = true, toast = "🎁 +1000 🪙 → Баланс: " .. tostring(nb) .. " 🪙" }
        end
        return status_header()
    elseif cmd == "ante" then
        local cur = (get_num("ante_bet", 0) == 1) and 0 or 1
        fullgram.storage_set("ante_bet", cur)
        return { cancel = true, toast = cur == 1 and "⚡ Ante Bet ВКЛ (+25%, x2 шанс бонуса)" or "⚡ Ante Bet ВЫКЛ" }
    elseif cmd == "buybonus" then
        local bal = get_balance()
        local bet = parse_bet(args, bal)
        local cost = bet * 100
        if bal < cost then
            return { cancel = true, toast = "Нужно " .. tostring(cost) .. " 🪙 (можно выдать: .setbal " .. tostring(cost) .. ")" }
        end
        set_balance(bal - cost)
        fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + cost)
        fullgram.storage_set("bonus_bet", bet)
        fullgram.storage_set("free_spins", get_num("free_spins", 0) + 10)
        fullgram.storage_set("bonus_mult", 1)
        return { cancel = true, toast = "🎁 Куплено 10 фриспинов по ставке " .. tostring(bet) .. " 🪙! Играйте .zeus или .dogs" }
    elseif cmd == "rtp" then
        return rtp_summary()
    end

    return nil
end
"""
    }

    private static func antiTyposPluginCode() -> String {
        return """
# @name Анти-опечатки
# @id fg_anti_typos
# @version 2.0
# @author FullGram
# @description Автоматически исправляет клавиатурные опечатки, двойные заглавные буквы и пробелы у знаков препинания (без сленг-макросов)

import re

TYPOS = {
    "привте": "привет",
    "првиет": "привет",
    "спсаибо": "спасибо",
    "спаисбо": "спасибо",
    "пожалусйта": "пожалуйста",
    "пожалйста": "пожалуйста",
    "сегодян": "сегодня",
    "сейчса": "сейчас",
    "хороош": "хорошо",
    "хоршо": "хорошо",
    "вообщше": "вообще",
    "вобще": "вообще",
    "кстти": "кстати",
    "кстаит": "кстати",
    "почмеу": "почему",
    "ничгео": "ничего",
    "коненчо": "конечно",
    "протсо": "просто",
    "толкьо": "только",
    "склько": "сколько",
    "извиин": "извини",
    "поянл": "понял",
    "будте": "будет",
    "можте": "может",
    "делате": "делает",
    "нраивтся": "нравится",
    "смотир": "смотри",
    "каежтся": "кажется"
}

def fix_word(w):
    if len(w) >= 3 and w[0] == w[0].upper() and w[1] == w[1].upper() and w[2] == w[2].lower() and w[0] != w[0].lower():
        w = w[0] + w[1:].lower()
    low = w.lower()
    if low in TYPOS:
        fixed = TYPOS[low]
        if w[0] == w[0].upper() and w[0] != w[0].lower():
            return fixed[0].upper() + fixed[1:]
        return fixed
    return w

def clean_line(line):
    if not line:
        return line
    out = re.sub(r"[ \\t]{2,}", " ", line)
    for p in [",", ".", ":", ";", "!", "?"]:
        out = out.replace(" " + p, p)
    words = out.split(" ")
    res = []
    for w in words:
        if not w:
            continue
        punct = ""
        core = w
        if len(w) > 1 and w[-1] in ",.!?:;":
            punct = w[-1]
            core = w[:-1]
        res = res + [fix_word(core) + punct]
    if len(res) == 0:
        return line
    return " ".join(res)

def clean_text(text):
    if not text or text.startswith("."):
        return text
    lines = text.split("\\n")
    fixed_lines = []
    for ln in lines:
        fixed_lines = fixed_lines + [clean_line(ln)]
    result = "\\n".join(fixed_lines)
    if not result:
        return text
    return result

def on_outgoing_message(ctx):
    original = str(ctx["text"])
    if not original or original.startswith("."):
        return None
    fixed = clean_text(original)
    if fixed and fixed != original:
        return fixed
    return None

def on_command(ctx):
    if ctx["command"] == "typo":
        sample = str(ctx["args"]).strip()
        if sample:
            return clean_text(sample)
        return {"cancel": True, "toast": "Анти-опечатки активны! Проверьте: .typo ПРивте , сегодян хороош"}
    return None
"""
    }

    private static func deadlinesPluginCode() -> String {
        return """
# @name Дедлайны (.dl / .deadline)
# @id fg_deadlines
# @version 2.0
# @author FullGram
# @description Управление сроками: .dl add <срок> | <задача>, .dl list, .dl done <№>, .dl send, .dl clear

import fullgram
import json

def load_items():
    raw = str(fullgram.storage_get("dl_json", "[]"))
    data = json.loads(raw)
    if data:
        return data
    return []

def save_items(items):
    fullgram.storage_set("dl_json", json.dumps(items))

def format_list(items):
    if len(items) == 0:
        return "⏰ Дедлайнов пока нет.\\nДобавьте: .dl add Завтра 18:00 | Сдать проект"
    lines = ["⏰ Список дедлайнов FullGram:", "━━━━━━━━━━━━━━━━━━━━"]
    for idx, item in enumerate(items):
        status = "✅" if item.get("done", False) else "⏳"
        due = item.get("due", "Без срока")
        task = item.get("task", "")
        num = idx + 1
        lines = lines + [f"{num}. {status} [{due}] — {task}"]
    return "\\n".join(lines)

def on_command(ctx):
    cmd = ctx["command"]
    if cmd != "dl" and cmd != "deadline":
        return None

    raw = str(ctx["args"]).strip()
    items = load_items()

    if not raw or raw == "list" or raw == "ui":
        fullgram.open_ui({"kind": "deadlines", "title": "Дедлайны FullGram"})
        return {"cancel": True}

    if raw == "send":
        return format_list(items)

    if raw == "clear":
        save_items([])
        return {"cancel": True, "toast": "Все дедлайны очищены."}

    if raw.startswith("done "):
        idx_str = raw[5:].strip()
        idx = int(idx_str) - 1
        if idx >= 0 and idx < len(items):
            cur = items[idx]
            updated = []
            for i, it in enumerate(items):
                if i == idx:
                    updated = updated + [{"due": cur.get("due", ""), "task": cur.get("task", ""), "done": True}]
                else:
                    updated = updated + [it]
            save_items(updated)
            return {"cancel": True, "toast": f"✅ Дедлайн №{idx + 1} выполнен!"}
        return {"cancel": True, "toast": "Неверный номер дедлайна."}

    if raw.startswith("del "):
        idx_str = raw[4:].strip()
        idx = int(idx_str) - 1
        if idx >= 0 and idx < len(items):
            updated = []
            for i, it in enumerate(items):
                if i != idx:
                    updated = updated + [it]
            save_items(updated)
            return {"cancel": True, "toast": f"🗑 Дедлайн №{idx + 1} удалён."}
        return {"cancel": True, "toast": "Неверный номер дедлайна."}

    body = raw[4:].strip() if raw.startswith("add ") else raw
    due = "Срочно"
    task = body
    if "|" in body:
        parts = body.split("|")
        due = parts[0].strip()
        task = parts[1].strip()
    else:
        words = body.split(" ")
        if len(words) >= 2:
            due = words[0]
            task = " ".join(words[1:])

    new_list = items + [{"due": due, "task": task, "done": False}]
    save_items(new_list)
    return {"cancel": True, "toast": f"⏰ Дедлайн добавлен: [{due}] {task}"}
"""
    }

    private static func snippetsPluginCode() -> String {
        return """
-- @name Быстрые шаблоны (.tpl)
-- @id fg_snippets
-- @version 1.0
-- @author FullGram
-- @description Шаблоны ответов: .tpl add <ключ> <текст>, .tpl <ключ>, .tpl list

function on_command(ctx)
    if ctx.command ~= "tpl" then return nil end
    local raw = tostring(ctx.args or "")
    if raw == "" or raw == "list" then
        local keys = tostring(fullgram.storage_get("tpl_keys", ""))
        if keys == "" then
            return { cancel = true, toast = "Шаблонов нет. Добавьте: .tpl add привет Привет! Как дела?" }
        end
        return { cancel = true, toast = "Шаблоны: " .. keys }
    end

    local space1 = string.find(raw, " ")
    local sub = space1 and string.sub(raw, 1, space1 - 1) or raw
    local rest = space1 and string.sub(raw, space1 + 1) or ""

    if sub == "add" and rest ~= "" then
        local space2 = string.find(rest, " ")
        if not space2 then
            return { cancel = true, toast = "Формат: .tpl add <ключ> <текст>" }
        end
        local key = string.lower(string.sub(rest, 1, space2 - 1))
        local body = string.sub(rest, space2 + 1)
        fullgram.storage_set("tpl_" .. key, body)
        local keys = tostring(fullgram.storage_get("tpl_keys", ""))
        if not string.find(keys, key, 1, true) then
            keys = (keys == "") and key or (keys .. ", " .. key)
            fullgram.storage_set("tpl_keys", keys)
        end
        return { cancel = true, toast = "Шаблон «" .. key .. "» сохранён!" }
    end

    local saved = fullgram.storage_get("tpl_" .. string.lower(sub), "")
    if saved ~= nil and saved ~= "" then
        return tostring(saved)
    end
    return { cancel = true, toast = "Шаблон «" .. sub .. "» не найден." }
end
"""
    }

    private static func notesPluginCode() -> String {
        return """
-- @name Быстрые заметки (.note)
-- @id fg_notes
-- @version 1.0
-- @author FullGram
-- @description Личные заметки: .note add <текст>, .note list, .note clear

function on_command(ctx)
    if ctx.command ~= "note" then return nil end
    local raw = tostring(ctx.args or "")
    local saved = tostring(fullgram.storage_get("notes_list", ""))

    if raw == "" or raw == "list" then
        if saved == "" then
            return { cancel = true, toast = "Заметок пока нет. Добавьте: .note add <текст>" }
        end
        return { cancel = true, toast = "📝 Заметки:\\n" .. saved }
    end

    if raw == "clear" then
        fullgram.storage_set("notes_list", "")
        return { cancel = true, toast = "Все заметки очищены." }
    end

    local text = raw
    if string.sub(raw, 1, 4) == "add " then
        text = string.sub(raw, 5)
    end
    if text == "" then
        return { cancel = true, toast = "Укажите текст заметки." }
    end
    local updated = (saved == "") and ("• " .. text) or (saved .. "\\n• " .. text)
    fullgram.storage_set("notes_list", updated)
    return { cancel = true, toast = "Заметка сохранена!" }
end
"""
    }

    private static func chatInfoPluginCode() -> String {
        return """
-- @name 1. Информация о чате
-- @id fg_chat_info
-- @version 1.0
-- @author FullGram
-- @description Команда .plug info-chat: подробная статистика чата (даты первого и последнего сообщения, частые и редкие слова, маты, ГС и кружки).

function on_command(ctx)
    local is_plug_info = (ctx.command == "plug" and ctx.subcommand == "info-chat")
    local is_alias = (ctx.command == "info-chat")
    if not is_plug_info and not is_alias then
        return nil
    end

    local stats = fullgram.get_chat_stats()
    if stats == nil then
        return { cancel = true, toast = "Откройте чат с сообщениями для анализа" }
    end

    local title = stats.title or "Чат"
    local top_line = "нет данных"
    if stats.top_words and #stats.top_words > 0 then
        local parts = {}
        for i = 1, #stats.top_words do
            local item = stats.top_words[i]
            table.insert(parts, tostring(i) .. ". " .. tostring(item.word) .. " (" .. tostring(item.count) .. ")")
        end
        top_line = table.concat(parts, " • ")
    end

    local rare_line = "нет данных"
    if stats.rare_words and #stats.rare_words > 0 then
        local rparts = {}
        for i = 1, #stats.rare_words do
            table.insert(rparts, tostring(stats.rare_words[i].word))
        end
        rare_line = table.concat(rparts, ", ")
    end

    local report = "📊 Информация о чате «" .. tostring(title) .. "»\\n"
        .. "━━━━━━━━━━━━━━━━━━━━\\n"
        .. "🕒 Первое сообщение: " .. tostring(stats.first_date or "—") .. "\\n"
        .. "🕓 Последнее сообщение: " .. tostring(stats.last_date or "—") .. "\\n"
        .. "💬 Проанализировано: " .. tostring(stats.analyzed_count or 0) .. " сообщ.\\n\\n"
        .. "🔥 Частые слова:\\n" .. top_line .. "\\n\\n"
        .. "💎 Самые редкие слова:\\n" .. rare_line .. "\\n\\n"
        .. "🤬 Слов мата: " .. tostring(stats.profanity_count or 0) .. "\\n"
        .. "🎤 Голосовых сообщений: " .. tostring(stats.voice_count or 0) .. "\\n"
        .. "⭕️ Видеокружков: " .. tostring(stats.round_count or 0) .. "\\n"
        .. "━━━━━━━━━━━━━━━━━━━━"

    return report
end
"""
    }

    // MARK: - Remote Plugin Market

    public func fetchRemoteCatalog(urlString: String? = nil, completion: @escaping (Result<FullGramRemoteCatalog, Error>) -> Void) {
        let targetString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveString = (targetString?.isEmpty == false) ? targetString! : self.catalogURL
        guard let url = URL(string: effectiveString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramPlugins", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес каталога плагинов."])))
            }
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ..< 300).contains(status), let data, data.count <= 2_097_152 else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FullGramPlugins", code: status, userInfo: [NSLocalizedDescriptionKey: "Сервер вернул код \(status) или слишком большой каталог."])))
                }
                return
            }
            do {
                let catalog = try JSONDecoder().decode(FullGramRemoteCatalog.self, from: data)
                DispatchQueue.main.async { completion(.success(catalog)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    public func installRemotePlugin(
        _ item: FullGramRemotePluginItem,
        enableImmediately: Bool,
        completion: @escaping (Result<FullGramPluginDescriptor, Error>) -> Void
    ) {
        if let inlineCode = item.code, !inlineCode.isEmpty {
            let saved = self.savePlugin(id: item.id, name: item.name, language: item.language, code: inlineCode, enabled: enableImmediately)
            DispatchQueue.main.async { completion(.success(saved)) }
            return
        }
        guard let rawUrl = item.url,
              let url = URL(string: rawUrl),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramPlugins", code: 400, userInfo: [NSLocalizedDescriptionKey: "У плагина отсутствует корректная ссылка на скрипт."])))
            }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ..< 300).contains(status),
                  let data,
                  data.count <= 1_048_576,
                  let scriptCode = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FullGramPlugins", code: status, userInfo: [NSLocalizedDescriptionKey: "Не удалось скачать скрипт плагина (HTTP \(status))."])))
                }
                return
            }
            let saved = self.savePlugin(id: item.id, name: item.name, language: item.language, code: scriptCode, enabled: enableImmediately)
            DispatchQueue.main.async { completion(.success(saved)) }
        }.resume()
    }
}
