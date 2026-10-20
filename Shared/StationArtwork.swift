import SwiftUI

struct StationBadge: View {
    let station: Station
    var body: some View {
        ZStack {
            Circle().fill(.teal.opacity(0.13))
            Text(station.shortTitle).font(.caption.weight(.bold))
                .multilineTextAlignment(.center).foregroundStyle(.primary)
                .padding(7)
        }.accessibilityHidden(true)
    }
}

/// Preloads the entire catalogue, with six requests at a time to protect playback.
@MainActor final class StationArtworkStore: ObservableObject {
    struct Entry {
        let image: UIImage
        let url: URL
        let end: Date
    }
    @Published private(set) var entries: [String: Entry] = [:]
    private func load(_ station: Station) async {
        let show = await ProgrammeCache.shared.show(for: station.id)
        guard !Task.isCancelled else { return }
        guard let show, let url = show.imageURL else {
            entries[station.id] = nil
            return
        }
        if let cached = entries[station.id], cached.url == url {
            entries[station.id] = Entry(image: cached.image, url: url, end: show.end)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 320, height: 320)) else { return }
        entries[station.id] = Entry(image: image, url: url, end: show.end)
    }
    func preload(_ stations: [Station]) async {
        while !Task.isCancelled {
            for start in stride(from: 0, to: stations.count, by: 6) {
                guard !Task.isCancelled else { return }
                await withTaskGroup(of: Void.self) { group in
                    for station in stations[start..<min(start + 6, stations.count)] {
                        group.addTask { await self.load(station) }
                    }
                }
            }
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }
}

struct StationProgrammeBadge: View {
    let station: Station
    let size: CGFloat
    @ObservedObject var artwork: StationArtworkStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if let entry = artwork.entries[station.id], entry.end > context.date {
                    Image(uiImage: entry.image).resizable().scaledToFill()
                } else {
                    StationBadge(station: station)
                }
            }.frame(width: size, height: size).clipShape(Circle())
        }.accessibilityHidden(true)
    }
}

