import AVFoundation
import Foundation

@main struct RewindPlaybackCheck {
    @MainActor static func main() async throws {
        let url = try await StreamConfiguration.playbackURL(for: .defaultStation)
        let player = AVPlayer(url: url); player.volume = 0; player.play()
        for _ in 0..<60 {
            if let item = player.currentItem, item.status == .failed { throw item.error ?? URLError(.cannotDecodeContentData) }
            if let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue,
               range.duration.seconds > 300, player.timeControlStatus == .playing { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard let item = player.currentItem, let range = item.seekableTimeRanges.last?.timeRangeValue else { fatalError("No DVR window") }
        let edge = CMTimeRangeGetEnd(range).seconds - 12
        for target in [edge - 120, edge - 60, edge] {
            let completed = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
            guard completed, abs(player.currentTime().seconds - target) < 3 else { fatalError("Seek failed") }
            print("PASS seek target=\(target), actual=\(player.currentTime().seconds), broadcastDate=\(String(describing: item.currentDate()))")
        }
        player.pause()
        print("PASS real AVPlayer: rewind 120s, forward 60s and return to live; window \(range.duration.seconds)s")
    }
}
