import Foundation

struct RadioShow: Equatable, Codable {
    let title: String
    let subtitle: String?
    let synopsis: String?
    let imageURL: URL?
    let start: Date
    let end: Date
}
struct RadioTrack: Equatable {
    let artist: String
    let title: String
}
enum BBCMetadata {
    struct Titles: Decodable { let primary: String?; let secondary: String? }
    struct Synopsis: Decodable { let short: String? }
    struct Artwork: Decodable { let url: String? }
    struct Programme: Decodable {
        let titles: Titles
        let synopses: Synopsis?
        let images: [Artwork]?
    }
    struct Broadcast: Decodable { let start: String; let end: String; let programme: Programme }
    struct Broadcasts: Decodable { let data: [Broadcast] }
    struct Offset: Decodable { let nowPlaying: Bool? }
    struct Segment: Decodable { let segmentType: String?; let titles: Titles; let offset: Offset? }
    struct Segments: Decodable { let data: [Segment] }
    static func currentShow(from data: Data, at now: Date) throws -> RadioShow? {
        let response = try JSONDecoder().decode(Broadcasts.self, from: data)
        let formatter = ISO8601DateFormatter()
        return response.data.compactMap { item -> RadioShow? in
            guard let start = formatter.date(from: item.start), let end = formatter.date(from: item.end),
                  start <= now, now < end, let title = item.programme.titles.primary else { return nil }
            let raw = item.programme.images?.first?.url?.replacingOccurrences(of: "{recipe}", with: "640x640")
            let url = raw.flatMap(URL.init(string:))
            let safeImage = url?.scheme == "https" && url?.host == "ichef.bbci.co.uk" ? url : nil
            return RadioShow(title: title, subtitle: item.programme.titles.secondary,
                             synopsis: item.programme.synopses?.short, imageURL: safeImage, start: start, end: end)
        }.first
    }
    static func currentTrack(from data: Data) throws -> RadioTrack? {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Segments.self, from: data)
        guard let item = response.data.first(where: { $0.segmentType == "music" && $0.offset?.nowPlaying == true }),
              let artist = item.titles.primary, let title = item.titles.secondary else { return nil }
        return RadioTrack(artist: artist, title: title)
    }
    static func fetch(_ path: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://rms.api.bbc.co.uk/v2/" + path)!)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
    static func show(for id: String) async -> RadioShow? {
        do { return try currentShow(from: await fetch("broadcasts/latest?service=\(id)&limit=100"), at: Date()) }
        catch { return nil }
    }
    static func track(for id: String) async -> RadioTrack? {
        do { return try currentTrack(from: await fetch("services/\(id)/segments/latest")) }
        catch { return nil }
    }
}



struct ProgrammeProgress: Equatable {
    let fraction: Double
    let elapsed: TimeInterval
    let remaining: TimeInterval
    static func calculate(start: Date, end: Date, now: Date) -> ProgrammeProgress? {
        let duration = end.timeIntervalSince(start)
        guard duration.isFinite, duration > 0, now.timeIntervalSince1970.isFinite else { return nil }
        let elapsed = min(duration, max(0, now.timeIntervalSince(start)))
        return ProgrammeProgress(fraction: elapsed / duration, elapsed: elapsed, remaining: duration - elapsed)
    }
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }
    var label: String { "\(Self.durationLabel(elapsed)) elapsed · \(Self.durationLabel(remaining)) remaining" }
}

actor ProgrammeCache {
    static let shared = ProgrammeCache()
    private var entries: [String: (show: RadioShow?, expires: Date)] = [:]
    func show(for id: String) async -> RadioShow? {
        let now = Date()
        if let entry = entries[id], entry.expires > now { return entry.show }
        let show = await BBCMetadata.show(for: id)
        let expiry = show.map { min($0.end, now.addingTimeInterval(300)) } ?? now.addingTimeInterval(20)
        entries[id] = (show, expiry)
        return show
    }
}

// BBC broadcast dates use Europe/London, including the 23/25-hour DST days.
enum BroadcastDate {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }
    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func adding(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }
    static func key(_ date: Date) -> String { let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    static func label(_ date: Date, now: Date = Date()) -> String {
        let delta = calendar.dateComponents([.day], from: day(now), to: day(date)).day
        if delta == 0 { return "Today" }; if delta == -1 { return "Yesterday" }; if delta == 1 { return "Tomorrow" }
        let f = DateFormatter(); f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM"; return f.string(from: date)
    }
    static func time(_ date: Date) -> String { let f = DateFormatter(); f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"; return f.string(from: date) }
}
struct ScheduledProgramme: Identifiable, Equatable, Codable {
    let id: String
    let episodeID: String
    let versionID: String?
    let show: RadioShow
    let availability: String?
    let availableUntil: Date?
    let blanked: Bool
    func isLive(at date: Date) -> Bool { show.start <= date && date < show.end }
    var soundsURL: URL? {
        guard episodeID.range(of: "^[a-z0-9]{8}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.bbc.co.uk/sounds/play/\(episodeID)")
    }
    func unavailable(at date: Date) -> Bool { blanked || (availableUntil.map { $0 <= date } ?? false) || ["expired", "unavailable"].contains(availability ?? "") }
}
enum ScheduleService {
    private struct Response: Decodable { let data: [Broadcast]; let total: Int }
    private struct Broadcast: Decodable { let pid: String; let start: String; let end: String; let blanked: Bool?; let programme: Programme }
    private struct Programme: Decodable {
        let id: String; let titles: BBCMetadata.Titles; let synopses: BBCMetadata.Synopsis?; let images: [BBCMetadata.Artwork]?; let availability: Availability?
    }
    private struct Availability: Decodable { let id: String?; let status: String?; let available_to_date: String? }
    static func decode(_ data: Data) throws -> (items: [ScheduledProgramme], total: Int) {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let f = ISO8601DateFormatter()
        let items = response.data.compactMap { b -> ScheduledProgramme? in
            guard let start = f.date(from: b.start), let end = f.date(from: b.end), start < end, let title = b.programme.titles.primary else { return nil }
            let image = b.programme.images?.first?.url?.replacingOccurrences(of: "{recipe}", with: "320x320")
            let url = image.flatMap(URL.init(string:))
            let show = RadioShow(title: title, subtitle: b.programme.titles.secondary, synopsis: b.programme.synopses?.short, imageURL: url?.host == "ichef.bbci.co.uk" && url?.scheme == "https" ? url : nil, start: start, end: end)
            return ScheduledProgramme(id: b.pid, episodeID: b.programme.id, versionID: b.programme.availability?.id, show: show, availability: b.programme.availability?.status, availableUntil: b.programme.availability?.available_to_date.flatMap(f.date(from:)), blanked: b.blanked ?? false)
        }
        return (items, response.total)
    }
    static func fetch(station: String, day: Date) async throws -> [ScheduledProgramme] {
        var items: [ScheduledProgramme] = []; var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try decode(await BBCMetadata.fetch("broadcasts?service=\(station)&date=\(BroadcastDate.key(day))&limit=100&offset=\(offset)"))
            items += page.items; offset += 100
            if offset >= page.total { break }
        }
        return items.sorted { $0.show.start < $1.show.start }
    }
}
actor ScheduleCache {
    static let shared = ScheduleCache()
    private var entries: [String: (Date, [ScheduledProgramme])] = [:]
    func load(station: String, day: Date, refresh: Bool = false) async throws -> [ScheduledProgramme] {
        let key = station + BroadcastDate.key(day)
        if !refresh, let e = entries[key], Date().timeIntervalSince(e.0) < 300 { return e.1 }
        let items = try await ScheduleService.fetch(station: station, day: day)
        entries[key] = (Date(), items)
        if entries.count > 80, let oldest = entries.min(by: { $0.value.0 < $1.value.0 })?.key { entries.removeValue(forKey: oldest) }
        return items
    }
}

// Independently implemented using BBC's returned HTTPS HLS connection, unchanged.
// Metadata and a version identifier alone never establish playback availability.
actor CatchupResolver {
    static let shared = CatchupResolver()
    private var verified: [String: (Date, URL)] = [:]
    private struct Response: Decodable { let media: [Media]? }
    private struct Media: Decodable { let connection: [Connection]? }
    private struct Connection: Decodable { let href: String?; let transferFormat: String? }
    func resolve(_ episode: ScheduledProgramme) async throws -> URL {
        guard episode.availability == "available", !episode.unavailable(at: Date()), episode.show.end <= Date(),
              let id = episode.versionID, id.range(of: "^[a-z0-9]{8}$", options: .regularExpression) != nil else { throw URLError(.resourceUnavailable) }
        if let cached = verified[id], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        var request = URLRequest(url: URL(string: "https://open.live.bbc.co.uk/mediaselector/6/select/version/2.0/mediaset/pc/vpid/\(id)/format/json")!); request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.resourceUnavailable) }
        let result = try JSONDecoder().decode(Response.self, from: data)
        let candidates = (result.media ?? []).flatMap { $0.connection ?? [] }
        for connection in candidates where connection.transferFormat == "hls" {
            guard let raw = connection.href, let url = URL(string: raw), url.scheme == "https", let host = url.host,
                  host.hasSuffix(".bbci.co.uk") || host.hasSuffix(".akamaized.net") else { continue }
            var check = URLRequest(url: url); check.timeoutInterval = 12
            if let (manifest, response) = try? await URLSession.shared.data(for: check), (response as? HTTPURLResponse)?.statusCode == 200,
               String(data: manifest, encoding: .utf8)?.hasPrefix("#EXTM3U") == true {
                verified[id] = (Date(), url); return url
            }
        }
        throw URLError(.resourceUnavailable)
    }
}

struct ListeningCheckpoint: Codable, Equatable, Identifiable {
    let stationID: String
    let programme: ScheduledProgramme?
    let position: Double
    let duration: Double
    let updated: Date
    let deviceID: String
    let deviceName: String
    let revision: String
    var id: String { programme.map { "episode." + $0.episodeID } ?? "live." + stationID }
    var resumePosition: Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return position >= duration - 10 ? 0 : max(0, min(position, duration))
    }
    func wins(over other: Self) -> Bool {
        updated != other.updated ? updated > other.updated : revision > other.revision
    }
}

