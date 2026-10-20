import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
check(Station.all.count == 71, "Complete BBC Sounds directory")
check(Set(Station.all.map(\.id)).count == 71, "Unique IDs")
for station in Station.all {
    check(Station.named(station.title) == station, "Canonical name: \(station.title)")
    check(Station.groups.contains(station.group), "Known group")
    for alias in station.aliases { check(Station.named(alias) == station, "Alias collision: \(alias)") }
}
for name in ["Six Music", "BBC Radio Six Music", "6 Music"] {
    check(Station.named(name)?.id == "bbc_6music", "6 Music alias")
}
check(Station.named("BBC Radio Four")?.id == "bbc_radio_fourfm", "Spoken number")
check(Station.named("Radio One Extra")?.id == "bbc_1xtra", "1Xtra alias")
check(Station.named("BBC Radio Cymru Two")?.id == "bbc_radio_cymru_2", "Nations alias")
check(Station.named("BBC Radio nan Gaidheal")?.id == "bbc_radio_nan_gaidheal", "Diacritics")
check(Station.named("Radio Five Live Sports Extra")?.id == "bbc_radio_five_live_sports_extra", "Sports alias")
for name in ["", "Radio", "Radio 99", "Taylor Swift", "Radio Four Podcast"] { check(Station.named(name) == nil, "Unsupported name: \(name)") }
let fixture = #"{"data":[{"start":"2026-10-20T10:00:00Z","end":"2026-10-20T11:00:00Z","programme":{"titles":{"primary":"Example show","secondary":"Episode"},"synopses":{"short":"Show description"},"images":[{"url":"https://ichef.bbci.co.uk/images/ic/{recipe}/example.jpg"}]}}]}"#.data(using: .utf8)!
let date = ISO8601DateFormatter().date(from: "2026-10-20T10:30:00Z")!
let show = try BBCMetadata.currentShow(from: fixture, at: date)
check(show?.title == "Example show", "Current programme parsed")
check(show?.imageURL?.absoluteString == "https://ichef.bbci.co.uk/images/ic/640x640/example.jpg", "BBC artwork")
let expired = try BBCMetadata.currentShow(from: fixture, at: date.addingTimeInterval(3600))
check(expired == nil, "Expired show not displayed")
let oldTrack = #"{"data":[{"segment_type":"music","titles":{"primary":"Artist","secondary":"Previous song"},"offset":{"now_playing":false}}]}"#.data(using: .utf8)!
let previous = try BBCMetadata.currentTrack(from: oldTrack)
check(previous == nil, "Previous track not now playing")
let trackData = #"{"data":[{"segment_type":"music","titles":{"primary":"Artist","secondary":"Current song"},"offset":{"now_playing":true}}]}"#.data(using: .utf8)!
let track = try BBCMetadata.currentTrack(from: trackData)
check(track?.title == "Current song" && track?.artist == "Artist", "Current track parsed")
print("PASS: 71 station identities and aliases, unsupported requests, show expiry, artwork URL and current-track parsing")
let full = RadioTimeline.make(start: 0, end: 21600, position: 21580, showStart: 18000)!
check(full.lower == 18000 && full.upper == 21588, "Rewind clipped to current show and safe live edge")
check(full.clamped(-100) == 18000 && full.clamped(99999) == 21588, "Seeks clamp both ends")
check(RadioTimeline.make(start: 100, end: 100, position: 100, showStart: nil) == nil, "Empty range unavailable")
check(RadioTimeline.make(start: 0, end: 100, position: .nan, showStart: nil) == nil, "Invalid times rejected")
check(RadioTimeline.make(start: 200, end: 300, position: 250, showStart: 100)?.lower == 200, "Expired buffer beats show start")
check(RadioTimeline.make(start: 0, end: 100, position: 90, showStart: 101) == nil, "No future programme seeking")
print("PASS: DVR boundaries, current-show clipping, moving buffer and live-edge clamping")

let favourites: Set<String> = [Station.all[5].id, Station.all[1].id]
let ordered = Station.ordered(favourites: favourites)
check(Array(ordered.prefix(2)) == [Station.all[1], Station.all[5]], "Stable favourites first")
check(ordered.count == Station.all.count && Set(ordered.map(\.id)).count == ordered.count, "No lost or duplicated stations")
let start = date
check(ProgrammeProgress.calculate(start: start, end: start.addingTimeInterval(3600), now: start.addingTimeInterval(1800))?.fraction == 0.5, "Halfway")
check(ProgrammeProgress.calculate(start: start, end: start, now: start) == nil, "Invalid duration")
check(ProgrammeProgress.calculate(start: start, end: start.addingTimeInterval(3600), now: start.addingTimeInterval(-1))?.fraction == 0, "Before start clamped")
check(ProgrammeProgress.calculate(start: start, end: start.addingTimeInterval(3600), now: start.addingTimeInterval(7200))?.fraction == 1, "After end clamped")
let iso = ISO8601DateFormatter()
let dstStart = iso.date(from: "2026-10-25T00:30:00+01:00")!
let dstEnd = iso.date(from: "2026-10-25T02:30:00Z")!
check(ProgrammeProgress.calculate(start: dstStart, end: dstEnd, now: dstStart.addingTimeInterval(5400))?.fraction == 0.5, "Overnight DST elapsed time")
print("PASS: stable favourites ordering and live programme progress, clamps, overnight/DST")

let seed = FavouriteChange(selected: true, timestamp: 0, revision: "migration")
let removal = FavouriteChange(selected: false, timestamp: 10, revision: "a")
let readdition = FavouriteChange(selected: true, timestamp: 11, revision: "b")
check(removal.wins(over: seed), "Cloud removal wins over migrated favourite")
check(readdition.wins(over: removal), "Later re-addition wins")
check(!removal.wins(over: readdition), "Older offline record does not overwrite newer record")
let tied = FavouriteChange(selected: true, timestamp: 10, revision: "b")
check(tied.wins(over: removal) && !removal.wins(over: tied), "Deterministic equal-time conflict resolution")
let savedChanges = ["bbc_6music": removal, "bbc_radio_one": readdition]
let decodedChanges = try JSONDecoder().decode([String: FavouriteChange].self, from: JSONEncoder().encode(savedChanges))
check(decodedChanges == savedChanges, "Favourite changes including removals survive persistence")
print("PASS: favourite migration, removal, re-addition, ordering, conflict resolution and persistence")
