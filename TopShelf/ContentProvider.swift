import TVServices
import Foundation
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let root = ShelfSnapshot.directory,
              let data = try? Data(contentsOf: root.appendingPathComponent("shelf.json")),
              let snapshot = try? JSONDecoder().decode(ShelfSnapshot.self, from: data) else { completionHandler(nil); return }
        func section(_ title: String, entries: [ShelfEntry]) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
            let items = entries.map { entry in
                let item = TVTopShelfSectionedItem(identifier: entry.id)
                item.title = entry.title; item.imageShape = .square
                let imageURL = entry.image.hasPrefix("https://") ? URL(string: entry.image) : root.appendingPathComponent(entry.image)
                item.setImageURL(imageURL, for: .screenScale1x)
                var link = URLComponents(); link.scheme = "soundslike"; link.host = "play"
                link.queryItems = [URLQueryItem(name: "station", value: entry.stationID)]
                if let checkpoint = entry.checkpointID { link.queryItems?.append(URLQueryItem(name: "checkpoint", value: checkpoint)) }
                if let url = link.url { item.displayAction = TVTopShelfAction(url: url); item.playAction = TVTopShelfAction(url: url) }
                return item
            }
            guard !items.isEmpty else { return nil }
            let result = TVTopShelfItemCollection(items: items); result.title = title; return result
        }
        let sections = [section("Favourites", entries: snapshot.favourites), section("Recently played", entries: snapshot.recent)].compactMap { $0 }
        completionHandler(sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections))
    }
}
