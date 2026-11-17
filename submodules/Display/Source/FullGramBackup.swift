import Foundation

public struct FullGramBackupPayload: Codable {
    public let version: Int
    public let exportedAt: TimeInterval
    public let boolDefaults: [String: Bool]
    public let intDefaults: [String: Int]
    public let doubleDefaults: [String: Double]
    public let stringDefaults: [String: String]
    public let stringArrayDefaults: [String: [String]]
    public let floatArrayDefaults: [String: [Float]]
    public let plugins: [FullGramPluginDescriptor]
}

public struct FullGramBackupInspection {
    public let settingsCount: Int
    public let pluginsCount: Int
    public let hasAntiScamWhitelist: Bool
    public let whitelistDomains: [String]
}

public enum FullGramBackup {
    public static let didRestoreNotification = Notification.Name("FullGram.BackupRestored")

    private static let trackedPrefixes = ["fullgram."]
    private static let excludedPrivacyKeys: Set<String> = [
        "fullgram.privacy.faceIdEnabled",
        "fullgram.privacy.lockedChats",
        "fullgram.plugins.catalogURL"
    ]
    private static let antiScamWhitelistKey = "fullgram.antiscam.whitelist"

    public static func exportToTemporaryFile() -> URL? {
        let dict = UserDefaults.standard.dictionaryRepresentation()
        var bools: [String: Bool] = [:]
        var ints: [String: Int] = [:]
        var doubles: [String: Double] = [:]
        var strings: [String: String] = [:]
        var stringArrays: [String: [String]] = [:]
        var floatArrays: [String: [Float]] = [:]

        for (key, value) in dict {
            guard Self.trackedPrefixes.contains(where: { key.hasPrefix($0) }) else { continue }
            guard !Self.excludedPrivacyKeys.contains(key) else { continue }
            if let n = value as? NSNumber {
                if CFGetTypeID(n) == CFBooleanGetTypeID() {
                    bools[key] = n.boolValue
                } else {
                    let d = n.doubleValue
                    if d == d.rounded() && abs(d) < Double(Int.max / 2) {
                        ints[key] = n.intValue
                    } else {
                        doubles[key] = d
                    }
                }
            } else if let s = value as? String {
                strings[key] = s
            } else if let arr = value as? [String] {
                stringArrays[key] = arr
            } else if let numArr = value as? [NSNumber] {
                floatArrays[key] = numArr.map { $0.floatValue }
            }
        }

        let payload = FullGramBackupPayload(
            version: 1,
            exportedAt: Date().timeIntervalSince1970,
            boolDefaults: bools,
            intDefaults: ints,
            doubleDefaults: doubles,
            stringDefaults: strings,
            stringArrayDefaults: stringArrays,
            floatArrayDefaults: floatArrays,
            plugins: FullGramPluginManager.shared.allPlugins()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm"
        let filename = "FullGram-Backup-\(df.string(from: Date())).fullgram"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    public static func inspectFile(url: URL) throws -> FullGramBackupInspection {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(FullGramBackupPayload.self, from: data)
        let domains = payload.stringArrayDefaults[Self.antiScamWhitelistKey] ?? []
        let totalSettings = payload.boolDefaults.count
            + payload.intDefaults.count
            + payload.doubleDefaults.count
            + payload.stringDefaults.count
            + payload.stringArrayDefaults.count
            + payload.floatArrayDefaults.count
        return FullGramBackupInspection(
            settingsCount: totalSettings,
            pluginsCount: payload.plugins.count,
            hasAntiScamWhitelist: !domains.isEmpty,
            whitelistDomains: domains
        )
    }

    public static func importFromFile(url: URL, allowAntiScamWhitelist: Bool = false) throws -> (settingsCount: Int, pluginsCount: Int) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(FullGramBackupPayload.self, from: data)

        var count = 0
        let defaults = UserDefaults.standard
        for (k, v) in payload.boolDefaults where !Self.excludedPrivacyKeys.contains(k) {
            defaults.set(v, forKey: k)
            count += 1
        }
        for (k, v) in payload.intDefaults where !Self.excludedPrivacyKeys.contains(k) {
            defaults.set(v, forKey: k)
            count += 1
        }
        for (k, v) in payload.doubleDefaults where !Self.excludedPrivacyKeys.contains(k) {
            defaults.set(v, forKey: k)
            count += 1
        }
        for (k, v) in payload.stringDefaults where !Self.excludedPrivacyKeys.contains(k) {
            defaults.set(v, forKey: k)
            count += 1
        }
        for (k, v) in payload.stringArrayDefaults {
            if Self.excludedPrivacyKeys.contains(k) { continue }
            if k == Self.antiScamWhitelistKey && !allowAntiScamWhitelist { continue }
            defaults.set(v, forKey: k)
            count += 1
        }
        for (k, v) in payload.floatArrayDefaults where !Self.excludedPrivacyKeys.contains(k) {
            defaults.set(v.map { NSNumber(value: $0) }, forKey: k)
            count += 1
        }

        // Security: do not import external plugin code from backups; plugins are only installed from the official FullGram market.
        NotificationCenter.default.post(name: FullGramMixer.didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramAntiScam.didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
        NotificationCenter.default.post(name: Self.didRestoreNotification, object: nil)

        return (count, 0)
    }
}
