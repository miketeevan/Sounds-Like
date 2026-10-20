import Foundation
@main struct ListeningCheckpointTests {
    static func main() throws {
        let show = RadioShow(title: "Offline test", subtitle: nil, synopsis: nil, imageURL: nil, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600))
        let programme = ScheduledProgramme(id: "broadcast", episodeID: "m000xzwq", versionID: "m000xzwp", show: show, availability: "available", availableUntil: nil, blanked: false)
        func record(_ position: Double, _ updated: Double, _ revision: String = "a") -> ListeningCheckpoint {
            ListeningCheckpoint(stationID: "bbc_6music", programme: programme, position: position, duration: 3600, updated: Date(timeIntervalSince1970: updated), deviceID: "test", deviceName: "iPad", revision: revision)
        }
        precondition(record(125, 2).resumePosition == 125)
        precondition(record(-50, 2).resumePosition == 0)
        precondition(record(3595, 2).resumePosition == 0)
        precondition(record(.nan, 2).resumePosition == 0)
        // Explicit backward seeks on another device must beat older, larger positions.
        precondition(record(100, 3).wins(over: record(2000, 2)))
        precondition(!record(2000, 2).wins(over: record(100, 3)))
        precondition(record(100, 3, "b").wins(over: record(100, 3, "a")))
        let decoded = try JSONDecoder().decode(ListeningCheckpoint.self, from: JSONEncoder().encode(record(125, 2)))
        precondition(decoded == record(125, 2))
        precondition(decoded.programme?.show.title == "Offline test")
        print("Listening checkpoint tests passed: resume, completion, invalid time, conflict order, round-trip metadata.")
    }
}
