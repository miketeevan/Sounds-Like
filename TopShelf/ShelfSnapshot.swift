import Foundation
struct ShelfEntry: Codable {
    let id: String
    let stationID: String
    let title: String
    let image: String
    let checkpointID: String?
}
struct ShelfSnapshot: Codable {
    static let group = "group.uk.mike.RadioBridge"
    let favourites: [ShelfEntry]
    let recent: [ShelfEntry]
    static var directory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let directory = container.appendingPathComponent("Library/Caches/TopShelf", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch { return nil }
    }
}
