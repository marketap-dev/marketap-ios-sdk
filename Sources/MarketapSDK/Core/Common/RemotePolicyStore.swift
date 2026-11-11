import Foundation

final class RemotePolicyStore {
    enum Block: String, CaseIterable {
        case collection, inApp, pushTracking
    }

    struct Rule: Codable {
        let mode: String
        let expiresAt: String?

        private static let fractionalFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        private static let formatter = ISO8601DateFormatter()

        func isStopped(at date: Date) -> Bool {
            guard mode == "stop" else { return false }
            guard let expiresAt = expiresAt else { return true }
            let expiry = Self.fractionalFormatter.date(from: expiresAt) ?? Self.formatter.date(from: expiresAt)
            return expiry.map { $0 > date } ?? true
        }
    }

    struct Policy: Codable {
        let revision: Int
        let refreshAfterSec: Int
        let collection: Rule?
        let inApp: Rule?
        let pushTracking: Rule?
        var sdkVersion: String? = nil
        var sdkType: String? = nil

        func rule(_ block: Block) -> Rule? {
            switch block {
            case .collection: return collection
            case .inApp: return inApp
            case .pushTracking: return pushTracking
            }
        }
    }

    static let keyPrefix = "marketap_sdk_policy."
    private let lock = NSRecursiveLock()
    private let defaults: UserDefaults
    private let projectId: String
    private let sdkVersion: String
    private let sdkType: String
    private let now: () -> Date
    private var stored: Policy?
    private var lastFetchedAt: Date?
    private var collectionStopped = false
    private var _collectionGeneration = 0
    var onCollectionStopped: (() -> Void)?

    init(projectId: String, sdkVersion: String = MarketapConfig.nativeSdkVersion, sdkType: String = MarketapConfig.nativeSdkType,
         defaults: UserDefaults = .standard, bundle: Bundle = .main,
         defaultsProvider: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) },
         now: @escaping () -> Date = Date.init) {
        self.projectId = projectId
        self.sdkVersion = sdkVersion
        self.sdkType = sdkType
        if let group = bundle.object(forInfoDictionaryKey: ClientKeyStore.appGroupInfoPlistKey) as? String, !group.isEmpty,
           let shared = defaultsProvider(group) {
            self.defaults = shared
        } else {
            self.defaults = defaults
        }
        self.now = now
        stored = self.defaults.data(forKey: Self.keyPrefix + projectId).flatMap { try? JSONDecoder().decode(Policy.self, from: $0) }
        if let policy = stored, policy.sdkVersion != sdkVersion || policy.sdkType != sdkType {
            stored = nil
            self.defaults.removeObject(forKey: Self.keyPrefix + projectId)
        }
        collectionStopped = stored?.collection?.isStopped(at: now()) ?? false
    }

    var revision: Int? {
        lock.lock(); defer { lock.unlock() }
        return stored?.revision
    }

    var collectionGeneration: Int {
        lock.lock(); defer { lock.unlock() }
        updateTransitions()
        return _collectionGeneration
    }

    var needsRefresh: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let lastFetchedAt = lastFetchedAt else { return true }
        return now().timeIntervalSince(lastFetchedAt) >= Double(stored?.refreshAfterSec ?? 300)
    }

    func isAllowed(_ block: Block) -> Bool {
        lock.lock(); defer { lock.unlock() }
        updateTransitions()
        return !(stored?.rule(block)?.isStopped(at: now()) ?? false)
    }

    @discardableResult
    func performIfAllowed(_ block: Block, generation: Int? = nil, _ action: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard isAllowed(block), generation == nil || generation == _collectionGeneration else { return false }
        action()
        return true
    }

    func received(_ payload: AnyCodable?) {
        lock.lock(); defer { lock.unlock() }
        lastFetchedAt = now()
        guard let payload = payload else {
            updateTransitions()
            return
        }
        guard let encoded = try? JSONEncoder().encode(payload), encoded.count <= 16 * 1024,
              let body = payload.value as? [String: Any] else { return }
        guard let version = body["version"] as? Int, version == 1 else { return }
        guard let revision = body["revision"] as? Int, revision > (stored?.revision ?? -1) else { return }
        let refresh = min(3600, max(60, body["refreshAfterSec"] as? Int ?? 300))
        func rule(_ block: Block) -> Rule? {
            guard let value = body[block.rawValue] else { return nil }
            guard let dict = value as? [String: Any], let mode = dict["mode"] as? String,
                  ["allow", "stop"].contains(mode) else { return stored?.rule(block) }
            return Rule(mode: mode, expiresAt: dict["expiresAt"] as? String)
        }
        let policy = Policy(revision: revision, refreshAfterSec: refresh,
                            collection: rule(.collection), inApp: rule(.inApp), pushTracking: rule(.pushTracking),
                            sdkVersion: sdkVersion, sdkType: sdkType)
        stored = policy
        if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: Self.keyPrefix + projectId) }
        updateTransitions()
    }

    private func updateTransitions() {
        let stopped = stored?.collection?.isStopped(at: now()) ?? false
        if collectionStopped != stopped {
            collectionStopped = stopped
            if stopped {
                _collectionGeneration += 1
                onCollectionStopped?()
            }
        }
    }
}
