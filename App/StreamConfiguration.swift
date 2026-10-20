import Foundation

enum StreamConfiguration {
    // BBC UK station manifests checked on 20 October 2026; no regional fallback.
    static func url(for station: Station) -> URL {
        URL(string: "https://a.files.bbci.co.uk/ms6/live/3441A116-B12E-4D2F-ACA8-C1984642FA4B/audio/simulcast/hls/uk/pc_hd_abr_v2/aks/\(station.id).m3u8")!
    }
    static func playbackURL(for station: Station) async throws -> URL {
        var request = URLRequest(url: url(for: station)); request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let manifest = String(data: data, encoding: .utf8), manifest.hasPrefix("#EXTM3U"),
              let line = manifest.components(separatedBy: .newlines).first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
              let mediaURL = URL(string: line), mediaURL.scheme == "https",
              mediaURL.host == "as-hls-uk-live.akamaized.net",
              mediaURL.path.hasSuffix(".norewind.m3u8") else { throw URLError(.badServerResponse) }
        // Same public UK stream with its server-provided DVR window. No downloads or proxy.
        return URL(string: mediaURL.absoluteString.replacingOccurrences(of: ".norewind.m3u8", with: ".m3u8"))!
    }

}

struct RadioTimeline: Equatable {
    let lower: Double
    let upper: Double
    let position: Double
    var duration: Double { upper - lower }
    var behindLive: Double { max(0, upper - position) }
    func clamped(_ value: Double) -> Double { min(upper, max(lower, value)) }
    static func make(start: Double, end: Double, position: Double, showStart: Double?, liveOffset: Double = 12) -> RadioTimeline? {
        guard start.isFinite, end.isFinite, position.isFinite, end > start else { return nil }
        let upper = end - min(max(3, liveOffset), (end - start) / 2)
        let lower = max(start, showStart?.isFinite == true ? showStart! : start)
        guard upper - lower >= 5 else { return nil }
        return RadioTimeline(lower: lower, upper: upper, position: position)
    }
}
