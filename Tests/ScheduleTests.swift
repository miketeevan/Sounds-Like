import Foundation
@main struct Checks {
 static func main() throws {
  let f = ISO8601DateFormatter()
  let autumn = BroadcastDate.day(f.date(from:"2026-10-25T12:00:00Z")!)
  assert(BroadcastDate.adding(1,to:autumn).timeIntervalSince(autumn)==25*3600)
  let spring = BroadcastDate.day(f.date(from:"2026-03-29T12:00:00Z")!)
  assert(BroadcastDate.adding(1,to:spring).timeIntervalSince(spring)==23*3600)
  let decoded = try ScheduleService.decode(Data(contentsOf:URL(fileURLWithPath:"Tests/Fixtures/bbc-schedule-2026-10-20.json")))
  assert(decoded.items.count == 14)
  for p in decoded.items { assert(p.isLive(at:p.show.start)); assert(!p.isLive(at:p.show.end)); assert(p.soundsURL != nil) }
  let first = decoded.items[0]
  assert(first.unavailable(at:Date.distantFuture))
  print("PASS real BBC schedule decode, programme boundaries, validated links, expiry, UK spring/autumn DST")
 }
}
