import Foundation
import Combine

struct FavouriteChange: Codable, Equatable {
    let selected: Bool
    let timestamp: Double
    let revision: String
    func wins(over other: FavouriteChange) -> Bool {
        timestamp != other.timestamp ? timestamp > other.timestamp : revision > other.revision
    }
}

/// One cloud key per station keeps independent edits on different devices independent.
@MainActor final class FavouriteStore: ObservableObject {
    static let shared = FavouriteStore()
    @Published private(set) var ids: Set<String> = []
    private let cloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    private var changes: [String: FavouriteChange] = [:]
    private var observer: NSObjectProtocol?
    private let prefix = "favourite.v2."
    private init() {
        if let data = local.data(forKey: "favouriteChanges.v2"),
           let saved = try? JSONDecoder().decode([String: FavouriteChange].self, from: data) { changes = saved }
        else {
            for id in local.stringArray(forKey: "favouriteStationIDs") ?? [] {
                changes[id] = FavouriteChange(selected: true, timestamp: 0, revision: "migration")
            }
        }
        publish()
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] notification in
            let accountChanged = (notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) == NSUbiquitousKeyValueStoreAccountChange
            Task { @MainActor in
                guard let self else { return }
                if accountChanged { self.changes = [:] }
                self.merge()
            }
        }
        cloud.synchronize()
        merge()
    }
    func toggle(_ id: String) {
        let previous = changes[id]?.timestamp ?? 0
        changes[id] = FavouriteChange(selected: !ids.contains(id), timestamp: max(Date().timeIntervalSince1970, previous + 0.001), revision: UUID().uuidString)
        persist(id)
        publish()
        cloud.synchronize()
    }
    private func merge() {
        for station in Station.all {
            let id = station.id
            let edit = cloud.data(forKey: prefix + id).flatMap { try? JSONDecoder().decode(FavouriteChange.self, from: $0) }
            // Migration seeds never overwrite later removals, even before initial cloud delivery.
            let seed = cloud.bool(forKey: "favourite.seed.v1." + id) ? FavouriteChange(selected: true, timestamp: 0, revision: "migration") : nil
            let remote = edit ?? seed
            if let remote, changes[id] == nil || remote.wins(over: changes[id]!) { changes[id] = remote }
            if let local = changes[id], remote == nil || local.wins(over: remote!) { persist(id) }
        }
        publish()
    }
    private func persist(_ id: String) {
        guard let change = changes[id] else { return }
        if change.timestamp == 0 { cloud.set(true, forKey: "favourite.seed.v1." + id) }
        else if let data = try? JSONEncoder().encode(change) { cloud.set(data, forKey: prefix + id) }
    }
    private func publish() {
        ids = Set(changes.filter { $0.value.selected }.map(\.key)).intersection(Station.all.map(\.id))
        local.set(try? JSONEncoder().encode(changes), forKey: "favouriteChanges.v2")
        local.set(ids.sorted(), forKey: "favouriteStationIDs")
    }
}
