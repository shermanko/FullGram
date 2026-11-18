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
        } else if ext == "lua" {
            language = .lua
        } else if code.contains("def on_") || code.contains("import fullgram") || code.contains("# @name") {
            language = .python
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
        self.hasRenderHooks = false
        guard self.isSystemEnabled else { return }

        var anyRender = false
        for descriptor in self.descriptors where descriptor.isEnabled {
            let runtime = self.compile(descriptor: descriptor)
            if runtime.hasRenderHook {
                anyRender = true
            }
            self.loaded[descriptor.id] = runtime
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
        return self.isSystemEnabled && !self.loaded.values.filter({ ($0.luaVM?.hasFunction("on_message_action") ?? false) || ($0.pythonVM?.hasFunction("on_message_action") ?? false) }).isEmpty
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
        do {
            if let lua = holder.luaVM, lua.hasFunction("on_ui_event") {
                return try lua.callFunction("on_ui_event", args: [.table(ctx)])
            } else if let py = holder.pythonVM, py.hasFunction("on_ui_event") {
                return try py.callFunction("on_ui_event", args: [.table(ctx)])
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
        guard self.isSystemEnabled && !self.loaded.isEmpty else {
            self.lock.unlock()
            return .pass
        }
        let orderedPlugins = self.descriptors.compactMap { self.loaded[$0.id] }
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
        guard self.isSystemEnabled && self.hasRenderHooks else {
            self.lock.unlock()
            return text
        }
        let renderPlugins = self.descriptors.compactMap { self.loaded[$0.id] }.filter { $0.hasRenderHook }
        self.lock.unlock()
        guard !renderPlugins.isEmpty else { return text }

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
                name: "Казино (.casino)",
                language: .lua,
                version: "3.0",
                author: "FullGram",
                description: "Напишите .casino — откроется графическое казино с выбором режима игры (Слоты 777, Рулетка, Монетка).",
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
-- @name Казино (.casino)
-- @id fg_casino
-- @version 3.0
-- @author FullGram
-- @description Напишите .casino — откроется графическое казино с выбором режима игры (Слоты 777, Рулетка, Монетка)

function get_balance()
    local b = tonumber(fullgram.storage_get("balance", 1000))
    if b == nil then return 1000 end
    return b
end

function set_balance(val)
    fullgram.storage_set("balance", val)
    local best = tonumber(fullgram.storage_get("best_balance", 1000)) or 1000
    if val > best then
        fullgram.storage_set("best_balance", val)
    end
end

function on_ui_event(ctx)
    local act = tostring(ctx.action or "")
    local bal = get_balance()
    local best = tonumber(fullgram.storage_get("best_balance", 1000)) or 1000
    if act == "bonus" then
        bal = bal + 1000
        set_balance(bal)
        best = tonumber(fullgram.storage_get("best_balance", 1000)) or 1000
    end
    return { balance = bal, best_balance = best }
end

function on_command(ctx)
    if ctx.command == "casino" then
        fullgram.open_ui({ kind = "casino", title = "Казино FullGram" })
        return { cancel = true }
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
