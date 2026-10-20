import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor final class ListeningHistory: ObservableObject {
    static let shared = ListeningHistory()
    @Published private(set) var records: [String: ListeningCheckpoint] = [:]
    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private let prefix = "listening.v1."
    private var observer: NSObjectProtocol?
    let deviceID: String
    var latest: ListeningCheckpoint? { records.values.max { $0.updated < $1.updated } }
    private init() {
        deviceID = defaults.string(forKey: "listening.device") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "listening.device")
        if let data = defaults.data(forKey: "listening.records"), let saved = try? JSONDecoder().decode([String: ListeningCheckpoint].self, from: data) { records = saved }
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] notification in
            let changedAccount = (notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) == NSUbiquitousKeyValueStoreAccountChange
            Task { @MainActor in
                guard let self else { return }
                if changedAccount { self.records = [:] }
                self.refresh()
            }
        }
        refresh()
    }
    func refresh() {
        cloud.synchronize()
        var merged = records
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(prefix) {
            guard let data = value as? Data, let remote = try? JSONDecoder().decode(ListeningCheckpoint.self, from: data),
                  remote.position.isFinite, remote.duration.isFinite,
                  Station.all.contains(where: { $0.id == remote.stationID }) else { continue }
            if merged[remote.id] == nil || remote.wins(over: merged[remote.id]!) { merged[remote.id] = remote }
        }
        records = Dictionary(uniqueKeysWithValues: merged.values.sorted { $0.updated > $1.updated }.prefix(60).map { ($0.id, $0) })
        saveLocal()
    }
    func save(station: Station, programme: ScheduledProgramme?, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite else { return }
        #if os(tvOS)
        let name = "Apple TV"
        #else
        let name = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
        let record = ListeningCheckpoint(stationID: station.id, programme: programme, position: max(0, position), duration: max(0, duration), updated: Date(), deviceID: deviceID, deviceName: name, revision: UUID().uuidString)
        records[record.id] = record
        if let data = try? JSONEncoder().encode(record) { cloud.set(data, forKey: prefix + record.id) }
        let old = records.values.sorted { $0.updated > $1.updated }.dropFirst(60)
        for record in old { records.removeValue(forKey: record.id); cloud.removeObject(forKey: prefix + record.id) }
        saveLocal(); cloud.synchronize()
    }
    private func saveLocal() { defaults.set(try? JSONEncoder().encode(records), forKey: "listening.records") }
}

struct ContinueListening: View {
    @ObservedObject var player: RadioPlayer
    @ObservedObject private var history = ListeningHistory.shared
    var body: some View {
        if let record = history.latest, !player.active, let station = Station.all.first(where: { $0.id == record.stationID }) {
            Button {
                if let programme = record.programme { player.playEpisode(programme, station: station) }
                else { player.play(station: station) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue listening").font(.caption).foregroundStyle(.secondary)
                        Text(record.programme?.show.title ?? station.title).font(.headline).lineLimit(1)
                        Text(record.programme == nil ? "\(station.title) · Live" : "\(ProgrammeProgress.durationLabel(record.resumePosition)) · \(record.deviceName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(12).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }
    }
}

#if os(iOS)
import AVFoundation
import UIKit

struct DownloadedShow: Codable, Identifiable {
    enum Status: String, Codable { case preparing, downloading, ready, failed }
    let id: String
    let programme: ScheduledProgramme
    let stationID: String
    var status: Status
    var progress: Double = 0
    var taskIdentifier: Int?
    var relativePath: String?
    var error: String?
    let created: Date
    var localURL: URL? { relativePath.map { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent($0) } }
}

private struct DownloadRequest: Codable {
    let programme: ScheduledProgramme
    let stationID: String
    let wanted: Bool
    let updated: Date
    let revision: String
    func wins(over other: Self) -> Bool {
        updated == other.updated ? revision > other.revision : updated > other.updated
    }
}

@MainActor final class DownloadLibrary: NSObject, ObservableObject, @preconcurrency AVAssetDownloadDelegate {
    static let shared = DownloadLibrary()
    static let sessionID = "uk.mike.RadioBridge.downloads.v1"
    @Published private(set) var shows: [DownloadedShow] = []
    @Published var message: String?
    var backgroundCompletion: (() -> Void)?
    private var preparing: [String: Task<Void, Never>] = [:]
    private var tasks: [String: AVAssetDownloadTask] = [:]
    private let manifest: URL
    private var session: AVAssetDownloadURLSession!
    private var restored = false
    private let cloud = NSUbiquitousKeyValueStore.default
    private let requestPrefix = "downloads.v1."
    private var requests: [String: DownloadRequest] = [:]
    private var cloudObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    override private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manifest = directory.appendingPathComponent("library.json")
        super.init()
        if let data = UserDefaults.standard.data(forKey: "downloads.requests"),
           let saved = try? JSONDecoder().decode([String: DownloadRequest].self, from: data) { requests = saved }
        cloudObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] notification in
            let accountChanged = (notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) == NSUbiquitousKeyValueStoreAccountChange
            Task { @MainActor in
                guard let self else { return }
                if accountChanged { self.requests = [:]; self.saveRequests() }
                self.refreshDownloads(migrate: !accountChanged)
            }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDownloads() }
        }
        if let data = try? Data(contentsOf: manifest), let stored = try? JSONDecoder().decode([DownloadedShow].self, from: data) { shows = stored }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: .main)
        session.getAllTasks { [weak self] restoredTasks in
            Task { @MainActor in
                guard let self else { return }
                for task in restoredTasks {
                    guard let asset = task as? AVAssetDownloadTask, let id = task.taskDescription, self.shows.contains(where: { $0.id == id }) else { task.cancel(); continue }
                    self.tasks[id] = asset
                }
                for index in self.shows.indices where [.preparing, .downloading].contains(self.shows[index].status) && self.tasks[self.shows[index].id] == nil {
                    self.shows[index].status = .failed; self.shows[index].error = "Download interrupted. Tap Retry."
                }
                self.restored = true; self.reconcile(); self.persist(); self.refreshDownloads()
            }
        }
    }
    private func saveRequests() {
        UserDefaults.standard.set(try? JSONEncoder().encode(requests), forKey: "downloads.requests")
    }
    private func publish(_ programme: ScheduledProgramme, stationID: String, wanted: Bool) {
        let request = DownloadRequest(programme: programme, stationID: stationID, wanted: wanted, updated: Date(), revision: UUID().uuidString)
        requests[programme.episodeID] = request
        saveRequests()
        if let data = try? JSONEncoder().encode(request) { cloud.set(data, forKey: requestPrefix + programme.episodeID) }
        cloud.synchronize()
    }
    func refreshDownloads(migrate: Bool = true) {
        guard restored else { return }
        cloud.synchronize()
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(requestPrefix) {
            guard let data = value as? Data, let remote = try? JSONDecoder().decode(DownloadRequest.self, from: data),
                  key == requestPrefix + remote.programme.episodeID,
                  Station.all.contains(where: { $0.id == remote.stationID }) else { continue }
            let id = remote.programme.episodeID
            if requests[id] == nil || remote.wins(over: requests[id]!) { requests[id] = remote }
        }
        // Upgrade existing local downloads once, without resurrecting cloud deletions.
        if migrate {
            for show in shows where requests[show.id] == nil {
                publish(show.programme, stationID: show.stationID, wanted: true)
            }
        }
        saveRequests()
        for (id, request) in requests {
            if !request.wanted { remove(id, sync: false) }
            else if entry(request.programme) == nil,
                    request.programme.availability == "available", !request.programme.unavailable(at: Date()),
                    let station = Station.all.first(where: { $0.id == request.stationID }) {
                download(request.programme, station: station, sync: false)
            }
            // Republish locally saved intentions after an offline change.
            let remote = cloud.data(forKey: requestPrefix + id).flatMap { try? JSONDecoder().decode(DownloadRequest.self, from: $0) }
            if remote?.revision != request.revision, let data = try? JSONEncoder().encode(request) {
                cloud.set(data, forKey: requestPrefix + id)
            }
        }
        cloud.synchronize()
    }
    func entry(_ programme: ScheduledProgramme) -> DownloadedShow? { shows.first { $0.id == programme.episodeID } }
    func localURL(for programme: ScheduledProgramme) -> URL? {
        guard !programme.unavailable(at: Date()), let entry = entry(programme), entry.status == .ready,
              let url = entry.localURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    func reconcile() {
        for index in shows.indices where shows[index].status == .ready {
            if shows[index].programme.unavailable(at: Date()) {
                shows[index].status = .failed; shows[index].error = "This show's availability has expired."
                if let url = shows[index].localURL { try? FileManager.default.removeItem(at: url) }
                shows[index].relativePath = nil
            } else if shows[index].localURL.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
                shows[index].status = .failed; shows[index].error = "This download is no longer on this device. Download it again."
                shows[index].relativePath = nil
            }
        }
        persist()
    }
    func download(_ programme: ScheduledProgramme, station: Station, sync: Bool = true) {
        guard restored else { message = "Restoring downloads. Please try again in a moment."; return }
        guard programme.show.end <= Date(), programme.availability == "available", !programme.unavailable(at: Date()) else {
            message = "This show isn't available to download."; return
        }
        if let existing = entry(programme), existing.status != .failed { return }
        if entry(programme) != nil { remove(programme.episodeID, sync: false) }
        if sync { publish(programme, stationID: station.id, wanted: true) }
        let id = programme.episodeID
        shows.insert(DownloadedShow(id: id, programme: programme, stationID: station.id, status: .preparing, created: Date()), at: 0)
        persist()
        preparing[id] = Task { [weak self] in
            do {
                let url = try await CatchupResolver.shared.resolve(programme)
                try Task.checkCancellation()
                guard let self, let index = self.shows.firstIndex(where: { $0.id == id }) else { return }
                let asset = AVURLAsset(url: url)
                guard let task = self.session.makeAssetDownloadTask(asset: asset, assetTitle: programme.show.title, assetArtworkData: nil, options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 128_000]) else {
                    throw URLError(.cannotCreateFile)
                }
                task.taskDescription = id
                self.tasks[id] = task; self.shows[index].taskIdentifier = task.taskIdentifier
                self.shows[index].status = .downloading; self.persist()
                task.resume()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.fail(id, "Couldn't download this show. \(error.localizedDescription)")
            }
            self?.preparing[id] = nil
        }
    }
    func remove(_ id: String, sync: Bool = true) {
        guard shows.contains(where: { $0.id == id }) else { return }
        RadioPlayer.shared.releaseDownload(id)
        preparing.removeValue(forKey: id)?.cancel()
        tasks.removeValue(forKey: id)?.cancel()
        if let show = shows.first(where: { $0.id == id }), let url = show.localURL {
            do { try FileManager.default.removeItem(at: url) }
            catch { if FileManager.default.fileExists(atPath: url.path) { message = "Couldn't delete this download. Please try again."; return } }
        }
        if sync, let show = shows.first(where: { $0.id == id }) { publish(show.programme, stationID: show.stationID, wanted: false) }
        shows.removeAll { $0.id == id }; persist()
    }
    private func persist() {
        do { try JSONEncoder().encode(shows).write(to: manifest, options: .atomic) }
        catch { message = "Couldn't save the download library. Check device storage." }
    }
    private func fail(_ id: String, _ text: String) {
        guard let index = shows.firstIndex(where: { $0.id == id }) else { return }
        shows[index].status = .failed; shows[index].error = text; persist()
    }
    private func rememberLocation(_ location: URL, task: AVAssetDownloadTask) {
        guard let id = task.taskDescription, shows.first(where: { $0.id == id })?.taskIdentifier == task.taskIdentifier,
              let index = shows.firstIndex(where: { $0.id == id }) else {
            try? FileManager.default.removeItem(at: location); return
        }
        let home = (URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/")
            .replacingOccurrences(of: "/private/var/", with: "/var/", options: .anchored)
        // AVFoundation can return a /.nofollow filesystem alias on physical iOS.
        // Store the path relative to the app container so installs preserve it.
        let unaliased = location.path.replacingOccurrences(of: "/.nofollow", with: "", options: .anchored)
        let resolved = URL(fileURLWithPath: unaliased).resolvingSymlinksInPath().path
        let path = resolved.replacingOccurrences(of: "/private/var/", with: "/var/", options: .anchored)
        guard path.hasPrefix(home) else {
            #if DOWNLOAD_VERIFICATION
            let debug = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("download-path.json")
            try? JSONSerialization.data(withJSONObject: ["path": path, "home": home, "url": location.absoluteString]).write(to: debug)
            #endif
            fail(id, "Couldn't save this download."); return
        }
        shows[index].relativePath = String(path.dropFirst(home.count)); persist()
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        rememberLocation(location, task: assetDownloadTask)
    }
    @available(iOS 18.0, *)
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        rememberLocation(location, task: assetDownloadTask)
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription, shows.first(where: { $0.id == id })?.taskIdentifier == assetDownloadTask.taskIdentifier,
              let index = shows.firstIndex(where: { $0.id == id }) else { return }
        let total = timeRangeExpectedToLoad.duration.seconds
        let loaded = loadedTimeRanges.reduce(0) { $0 + $1.timeRangeValue.duration.seconds }
        if total.isFinite, total > 0, loaded.isFinite { shows[index].progress = min(1, max(0, loaded / total)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, shows.first(where: { $0.id == id })?.taskIdentifier == task.taskIdentifier else { return }
        tasks[id] = nil
        guard let index = shows.firstIndex(where: { $0.id == id }) else { return }
        if let error { fail(id, error.localizedDescription); return }
        guard let url = shows[index].localURL, FileManager.default.fileExists(atPath: url.path),
              AVURLAsset(url: url).assetCache?.isPlayableOffline == true else {
            fail(id, "The download isn't complete enough for offline playback. Please retry."); return
        }
        shows[index].status = .ready; shows[index].progress = 1; shows[index].error = nil
        persist()
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = backgroundCompletion; backgroundCompletion = nil; completion?()
    }
}

struct DownloadMenu: View {
    let programme: ScheduledProgramme
    let station: Station
    @ObservedObject private var library = DownloadLibrary.shared
    var body: some View {
        if let entry = library.entry(programme) {
            if entry.status == .ready {
                Label("Downloaded on this device", systemImage: "checkmark.circle")
                Button("Delete download", role: .destructive) { library.remove(entry.id) }
            } else if entry.status == .failed {
                Button("Retry download", systemImage: "arrow.clockwise") { library.download(programme, station: station) }
                Button("Remove download", role: .destructive) { library.remove(entry.id) }
            } else {
                Button("Cancel download", role: .destructive) { library.remove(entry.id) }
            }
        } else if programme.show.end <= Date(), programme.availability == "available", !programme.unavailable(at: Date()) {
            Button("Download show", systemImage: "arrow.down.circle") { library.download(programme, station: station) }
        } else {
            Label("Download unavailable", systemImage: "arrow.down.circle")
        }
    }
}

struct DownloadsView: View {
    @ObservedObject private var library = DownloadLibrary.shared
    @ObservedObject var player: RadioPlayer
    @State private var deleting: DownloadedShow?
    var body: some View {
        NavigationStack {
            List {
                if library.shows.isEmpty {
                    ContentUnavailableView("No downloads yet", systemImage: "arrow.down.circle", description: Text("Press and hold a past show in Schedules, then choose Download show. Downloads sync to your iPhone and iPad through iCloud. Open Sounds Like on each device to download its offline copy."))
                }
                ForEach(library.shows) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(entry.programme.show.title).font(.headline)
                        Text(Station.all.first(where: { $0.id == entry.stationID })?.title ?? entry.stationID).font(.subheadline).foregroundStyle(.secondary)
                        Text(BroadcastDate.label(entry.programme.show.start) + " · " + ProgrammeProgress.durationLabel(entry.programme.show.end.timeIntervalSince(entry.programme.show.start))).font(.caption).foregroundStyle(.secondary)
                        switch entry.status {
                        case .preparing: ProgressView("Preparing download…")
                        case .downloading: ProgressView(value: entry.progress) { Text("Downloading \(Int(entry.progress * 100))%") }
                        case .ready:
                            HStack {
                                Button { if let station = Station.all.first(where: { $0.id == entry.stationID }) { player.playEpisode(entry.programme, station: station) } } label: { Label("Play offline", systemImage: "play.fill") }.buttonStyle(.borderedProminent).tint(.teal)
                                if player.episode?.episodeID == entry.id { Button(player.active ? "Pause" : "Resume", action: player.toggle).buttonStyle(.bordered) }
                            }
                            if let expiry = entry.programme.availableUntil { Text("Available until \(expiry.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                        case .failed:
                            Text(entry.error ?? "Download failed").font(.caption).foregroundStyle(.secondary)
                            if let station = Station.all.first(where: { $0.id == entry.stationID }), !entry.programme.unavailable(at: Date()) {
                                Button("Retry download") { library.download(entry.programme, station: station) }.buttonStyle(.bordered)
                            }
                        }
                    }.padding(.vertical, 8)
                        .swipeActions { Button("Delete", role: .destructive) { deleting = entry } }
                        .contextMenu { Button("Delete download", role: .destructive) { deleting = entry } }
                }.onDelete { offsets in if let index = offsets.first { deleting = library.shows[index] } }
            }.navigationTitle("Downloads")
                .toolbar { EditButton() }
                .confirmationDialog("Delete this download?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete download", role: .destructive) {
                        if let entry = deleting {
                            if player.episode?.episodeID == entry.id { player.pause() }
                            library.remove(entry.id)
                        }
                        deleting = nil
                    }
                } message: { Text("This deletes the download from your iPhone and iPad when they next sync. Your listening position is kept.") }
                .onAppear { library.reconcile(); library.refreshDownloads() }
        }
    }
}
#endif

#if os(iOS)
struct DownloadMessageAlert: ViewModifier {
    @ObservedObject private var library = DownloadLibrary.shared
    func body(content: Content) -> some View {
        content.alert("Downloads", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK") { library.message = nil }
        } message: { Text(library.message ?? "") }
    }
}
#endif

#if DOWNLOAD_VERIFICATION && os(iOS)
import Foundation
import AVFoundation
@MainActor enum DownloadVerification {
    static func verifyRelaunch() async {
        let report = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("download-verification.json")
        var result = ((try? Data(contentsOf: report)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }) ?? [:]
        do {
            try await Task.sleep(for: .seconds(3))
            guard let id = result["episode"], let entry = DownloadLibrary.shared.shows.first(where: { $0.id == id }),
                  let station = Station.all.first(where: { $0.id == entry.stationID }),
                  let url = DownloadLibrary.shared.localURL(for: entry.programme) else { throw URLError(.fileDoesNotExist) }
            result["restoredDownload"] = "true"
            RadioPlayer.shared.playEpisode(entry.programme, station: station)
            for _ in 0..<30 {
                try await Task.sleep(for: .seconds(1))
                if RadioPlayer.shared.state == .playing { break }
            }
            guard RadioPlayer.shared.state == .playing else { throw URLError(.cannotDecodeContentData) }
            result["resumedPosition"] = String(RadioPlayer.shared.episodePosition)
            RadioPlayer.shared.pause()
            DownloadLibrary.shared.remove(entry.id)
            result["deletedAudio"] = String(!FileManager.default.fileExists(atPath: url.path))
            result["deletedEntry"] = String(DownloadLibrary.shared.entry(entry.programme) == nil)
            result["checkpointRetained"] = String(ListeningHistory.shared.records["episode." + entry.id] != nil)
            result["stage"] = "relaunch, resume and deletion passed"
        } catch { result["stage"] = "relaunch failed"; result["failure"] = String(describing: error) }
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: report, options: .atomic)
    }
    static func run() async {
        if ProcessInfo.processInfo.arguments.contains("--verify-download-relaunch") {
            await verifyRelaunch(); return
        }
        guard ProcessInfo.processInfo.arguments.contains("--verify-download") else { return }
        let report = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("download-verification.json")
        var result: [String: String] = [:]
        func write(_ stage: String) { result["stage"] = stage; try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: report, options: .atomic) }
        write("fetching")
        do {
            let station = Station.all.first { $0.id == "bbc_radio_four_extra" }!
            let items = try await ScheduleCache.shared.load(station: station.id, day: BroadcastDate.adding(-1, to: Date()))
            let candidates = items.filter { $0.availability == "available" && !$0.unavailable(at: Date()) }.sorted { $0.show.end.timeIntervalSince($0.show.start) < $1.show.end.timeIntervalSince($1.show.start) }
            guard let programme = candidates.first(where: { DownloadLibrary.shared.entry($0)?.status != .ready }) else { throw URLError(.resourceUnavailable) }
            result["episode"] = programme.episodeID; result["title"] = programme.show.title
            try await Task.sleep(for: .seconds(2))
            DownloadLibrary.shared.download(programme, station: station)
            write("downloading")
            var ready = false
            for _ in 0..<240 {
                try await Task.sleep(for: .seconds(1))
                guard let entry = DownloadLibrary.shared.entry(programme) else { throw URLError(.fileDoesNotExist) }
                result["progress"] = String(entry.progress)
                if entry.status == .failed { result["error"] = entry.error; throw URLError(.cannotLoadFromNetwork) }
                if entry.status == .ready { ready = true; break }
                write("downloading")
            }
            guard ready, let local = DownloadLibrary.shared.localURL(for: programme) else { throw URLError(.timedOut) }
            result["offlineAsset"] = String(AVURLAsset(url: local).assetCache?.isPlayableOffline == true)
            result["localFile"] = String(local.isFileURL)
            write("testing local playback")
            RadioPlayer.shared.playEpisode(programme, station: station)
            for _ in 0..<30 {
                try await Task.sleep(for: .seconds(1))
                if RadioPlayer.shared.state == .playing { break }
            }
            guard RadioPlayer.shared.state == .playing else { throw URLError(.cannotDecodeContentData) }
            RadioPlayer.shared.seek(to: 125)
            try await Task.sleep(for: .seconds(4))
            RadioPlayer.shared.pause()
            result["savedPosition"] = String(ListeningHistory.shared.records["episode." + programme.episodeID]?.position ?? -1)
            write("ready for relaunch")
        } catch {
            result["failure"] = String(describing: error); write("failed")
        }
    }
}
#endif
