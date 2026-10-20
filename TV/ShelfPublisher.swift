import Foundation
import UIKit
import TVServices
@MainActor enum ShelfPublisher {
    static func update(artwork: StationArtworkStore) {
        guard let root = ShelfSnapshot.directory else { return }
        let history = ListeningHistory.shared.records.values.sorted { $0.updated > $1.updated }
        func entry(station: Station, checkpoint: ListeningCheckpoint? = nil) -> ShelfEntry {
            let filename = "station-" + station.id + ".jpg"
            let image = artwork.entries[station.id]?.image ?? UIImage(named: "ShelfFallback")
            if let data = image?.jpegData(compressionQuality: 0.85) { try? data.write(to: root.appendingPathComponent(filename), options: .atomic) }
            return ShelfEntry(id: checkpoint?.id ?? station.id, stationID: station.id,
                title: checkpoint?.programme?.show.title ?? station.title, image: checkpoint?.programme?.show.imageURL?.absoluteString ?? filename, checkpointID: checkpoint?.id)
        }
        let favourites = Station.ordered(favourites: FavouriteStore.shared.ids).filter { FavouriteStore.shared.ids.contains($0.id) }.prefix(12).map { entry(station: $0) }
        let recent = history.prefix(8).compactMap { record in
            Station.all.first(where: { $0.id == record.stationID }).map { entry(station: $0, checkpoint: record) }
        }
        let snapshot = ShelfSnapshot(favourites: favourites, recent: recent)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let path = root.appendingPathComponent("shelf.json")
        try? data.write(to: path, options: .atomic)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
    static func open(_ url: URL) {
        guard url.scheme == "soundslike", url.host == "play", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = parts.queryItems?.first(where: { $0.name == "station" })?.value,
              let station = Station.all.first(where: { $0.id == id }) else { return }
        ListeningHistory.shared.refresh()
        if let key = parts.queryItems?.first(where: { $0.name == "checkpoint" })?.value,
           let record = ListeningHistory.shared.records[key], record.stationID == station.id,
           let programme = record.programme, !programme.unavailable(at: Date()) {
            RadioPlayer.shared.playEpisode(programme, station: station)
        } else { RadioPlayer.shared.play(station: station) }
    }
}
