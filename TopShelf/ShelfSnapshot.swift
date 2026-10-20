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
    static var directory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
}
