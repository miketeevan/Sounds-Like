import AVFoundation
import MediaPlayer
import Combine
import UIKit
#if os(iOS)
import Intents
#endif

@MainActor final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()
    enum State: Equatable { case paused, connecting, playing, error(String) }
    @Published private(set) var favouriteIDs = Set(UserDefaults.standard.stringArray(forKey: "favouriteStationIDs") ?? [])
    @Published private(set) var station = Station.defaultStation
    @Published private(set) var state: State = .paused
    @Published private(set) var nowPlayingShow: RadioShow?
    @Published private(set) var nowPlayingTrack: RadioTrack?
    @Published private(set) var showArtwork: UIImage?
    @Published private(set) var timeline: RadioTimeline?
    @Published private(set) var seekError: String?
    @Published private(set) var hasPlaybackSession = false
    @Published private(set) var episode: ScheduledProgramme?
    @Published private(set) var episodePosition: Double = 0
    @Published private(set) var episodeDuration: Double = 0
    var isRewound: Bool { episode == nil && (timeline?.behindLive ?? 0) > 15 }
    private var lastCheckpoint = Date.distantPast
    private var periodicObserver: Any?
    private var sourceTask: Task<Void, Never>?
    private var sourceGeneration = UUID()
    private var seekGeneration = UUID()
    private var pendingDonationStation: String?
    private var metadataTask: Task<Void, Never>?
    private var artworkURL: URL?
    private let player = AVPlayer()
    private var wantsPlayback = false
    private var interrupted = false
    private var retries = 0
    private var retry: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var timeObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    var active: Bool { wantsPlayback }

    private var favouriteSubscription: AnyCancellable?
    private init() {
        favouriteSubscription = FavouriteStore.shared.$ids.sink { [weak self] in self?.favouriteIDs = $0 }
        if let id = UserDefaults.standard.string(forKey: "station"), let saved = Station.all.first(where: { $0.id == id }) { station = saved }
        timeObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.wantsPlayback else { return }
                if self.player.timeControlStatus == .playing {
                    self.donateSuccessfulPlayback()
                    self.state = .playing; self.retries = 0; self.timeout?.cancel(); self.timeout = nil; self.metadata()
                } else if self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.state = .connecting; self.armTimeout()
                }
            }
        }
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTimeline()
                if let self, self.state == .playing, Date().timeIntervalSince(self.lastCheckpoint) >= 15 { self.saveCheckpoint() }
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.episode != nil, let item = notification.object as? AVPlayerItem, self.player.currentItem === item else { return }
                self.pause(); self.player.seek(to: .zero); self.episodePosition = 0
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.interrupted = self.wantsPlayback
                    self.cancelSourceAndTimeline()
                    self.retry?.cancel(); self.timeout?.cancel(); self.player.pause(); self.state = .paused; self.metadata()
                } else {
                    let resume = self.interrupted && self.wantsPlayback && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.interrupted = false
                    if resume { self.startFresh() } else { self.pause() }
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.wantsPlayback == true { self?.startFresh() } }
        })
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.stopCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.changePlaybackPositionCommand.isEnabled = false
        commands.skipBackwardCommand.preferredIntervals = [30]
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-30) }; return .success }
        commands.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(30) }; return .success }
        commands.skipBackwardCommand.isEnabled = false
        commands.skipForwardCommand.isEnabled = false
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
    }
    func toggleFavourite(_ station: Station) {
        FavouriteStore.shared.toggle(station.id)
    }
    func select(_ next: Station) {
        guard next != station || episode != nil else { return }
        saveCheckpoint()
        episode = nil; episodePosition = 0; episodeDuration = 0
        let wasPlaying = wantsPlayback
        retry?.cancel(); timeout?.cancel(); timeout = nil; statusObservation = nil
        cancelSourceAndTimeline()
        player.pause(); player.replaceCurrentItem(with: nil)
        artworkURL = nil
        pendingDonationStation = wasPlaying ? next.id : nil
        station = next; UserDefaults.standard.set(next.id, forKey: "station")
        nowPlayingShow = nil; nowPlayingTrack = nil; showArtwork = nil
        startMetadata()
        if wasPlaying { retries = 0; startFresh() } else { state = .paused; metadata() }
    }
    func play(station: Station) {
        select(station); play()
        // Siri already records its own interaction; do not duplicate that signal.
        pendingDonationStation = nil
    }
    func playEpisode(_ programme: ScheduledProgramme, station: Station) {
        pause(); statusObservation = nil; cancelSourceAndTimeline(); player.replaceCurrentItem(with: nil); self.episode = programme; self.station = station
        ListeningHistory.shared.refresh()
        episodePosition = ListeningHistory.shared.records["episode." + programme.episodeID]?.resumePosition ?? 0
        episodeDuration = programme.show.end.timeIntervalSince(programme.show.start)
        nowPlayingShow = programme.show; nowPlayingTrack = nil; showArtwork = nil
        play()
    }
    func releaseDownload(_ id: String) {
        guard episode?.episodeID == id else { return }
        pause(); statusObservation = nil; cancelSourceAndTimeline(); player.replaceCurrentItem(with: nil)
    }
    func toggle() { active ? pause() : play() }
    func play() {
        guard !wantsPlayback else { return }
        pendingDonationStation = episode == nil ? station.id : nil
        hasPlaybackSession = true; wantsPlayback = true; retries = 0; startMetadata()
        if episode != nil, player.currentItem?.status == .readyToPlay {
            try? AVAudioSession.sharedInstance().setActive(true); player.play()
        } else { startFresh() }
    }
    func pause() {
        saveCheckpoint()
        pendingDonationStation = nil
        wantsPlayback = false; interrupted = false
        retry?.cancel(); retry = nil; timeout?.cancel(); timeout = nil
        if episode == nil { statusObservation = nil; cancelSourceAndTimeline(); player.pause(); player.replaceCurrentItem(with: nil) }
        else { sourceTask?.cancel(); sourceGeneration = UUID(); episodePosition = player.currentTime().seconds.isFinite ? player.currentTime().seconds : episodePosition; player.pause() }
        state = .paused; metadata()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func startFresh() {
        guard wantsPlayback, !interrupted else { return }
        retry?.cancel(); timeout?.cancel(); timeout = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch { fail("Audio session: \(error.localizedDescription)"); return }
        state = .connecting
        cancelSourceAndTimeline()
        statusObservation = nil; player.pause(); player.replaceCurrentItem(with: nil)
        let generation = sourceGeneration
        let selected = station
        let selectedEpisode = episode
        let resumePosition = episodePosition
        armTimeout()
        sourceTask = Task { [weak self] in
            do {
                let url: URL
                if let selectedEpisode {
                    #if os(iOS)
                    if let local = DownloadLibrary.shared.localURL(for: selectedEpisode) { url = local }
                    else { url = try await CatchupResolver.shared.resolve(selectedEpisode) }
                    #else
                    url = try await CatchupResolver.shared.resolve(selectedEpisode)
                    #endif
                }
                else { url = try await StreamConfiguration.playbackURL(for: selected) }
                guard let self, !Task.isCancelled, self.wantsPlayback, !self.interrupted, self.sourceGeneration == generation else { return }
                let item = AVPlayerItem(url: url)
                self.statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self, self.player.currentItem === item, self.wantsPlayback else { return }
                        if item.status == .failed { self.fail(item.error?.localizedDescription ?? "The live stream is unavailable.") }
                    }
                }
                self.player.replaceCurrentItem(with: item)
                if selectedEpisode != nil, resumePosition > 0 { await self.player.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 600)) }
                guard !Task.isCancelled, self.sourceGeneration == generation else { return }
                self.player.play(); self.metadata()
            } catch {
                guard let self, !Task.isCancelled, self.sourceGeneration == generation else { return }
                self.fail("Unable to load audio: \(error.localizedDescription)")
            }
        }
    }
    private func cancelSourceAndTimeline() {
        sourceGeneration = UUID(); seekGeneration = UUID(); sourceTask?.cancel(); sourceTask = nil
        player.currentItem?.cancelPendingSeeks()
        timeline = nil; seekError = nil
        MPRemoteCommandCenter.shared().skipBackwardCommand.isEnabled = false
        MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled = false
    }
    private func refreshTimeline() {
        if episode != nil, let item = player.currentItem {
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 { episodeDuration = duration }
            let position = player.currentTime().seconds
            if position.isFinite { episodePosition = position }
            if episodeDuration > 0 { timeline = RadioTimeline(lower: 0, upper: episodeDuration, position: episodePosition) }
            MPRemoteCommandCenter.shared().skipBackwardCommand.isEnabled = true
            MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled = true
            metadata(); return
        }
        let wasRewound = isRewound
        guard wantsPlayback, !interrupted, let item = player.currentItem,
              let range = item.seekableTimeRanges.last?.timeRangeValue else {
            timeline = nil
            MPRemoteCommandCenter.shared().skipBackwardCommand.isEnabled = false
            MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled = false
            return
        }
        let position = item.currentTime().seconds
        let start = range.start.seconds
        let end = CMTimeRangeGetEnd(range).seconds
        let showStart: Double?
        if let date = item.currentDate(), let show = nowPlayingShow {
            showStart = position + show.start.timeIntervalSince(date)
        } else { showStart = nil }
        let offset = item.recommendedTimeOffsetFromLive.seconds
        timeline = RadioTimeline.make(start: start, end: end, position: position, showStart: showStart, liveOffset: offset.isFinite ? offset : 12)
        let enabled = timeline != nil
        MPRemoteCommandCenter.shared().skipBackwardCommand.isEnabled = enabled
        MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled = enabled
        if wasRewound != isRewound { metadata() }
    }
    func seek(to seconds: Double) {
        refreshTimeline()
        guard seconds.isFinite, (wantsPlayback || episode != nil), !interrupted, let window = timeline, let item = player.currentItem else { return }
        let token = UUID(); seekGeneration = token; seekError = nil
        item.cancelPendingSeeks()
        player.seek(to: CMTime(seconds: window.clamped(seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)) { [weak self] completed in
            Task { @MainActor in
                guard let self, self.seekGeneration == token, self.player.currentItem === item else { return }
                if !completed { self.seekError = "That part of the broadcast is no longer available. Try again or return to live." }
                self.refreshTimeline(); self.saveCheckpoint(); self.metadata()
            }
        }
    }
    func skip(_ seconds: Double) { seek(to: player.currentTime().seconds + seconds) }
    func backToLive() {
        if episode != nil { let selected = station; select(selected); play(); return }
        refreshTimeline()
        if let window = timeline { seek(to: window.upper) } else if !wantsPlayback { play() }
    }

    private func armTimeout() {
        guard timeout == nil else { return }
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }
            guard let self, self.wantsPlayback, !self.interrupted else { return }
            self.timeout = nil
            self.fail("The stream did not respond. Check Wi-Fi and try again.")
        }
    }
    private func fail(_ message: String) {
        guard wantsPlayback, !interrupted else { return }
        timeout?.cancel(); timeout = nil; statusObservation = nil
        cancelSourceAndTimeline()
        player.pause(); player.replaceCurrentItem(with: nil)
        retries += 1
        guard retries <= 3 else {
            wantsPlayback = false; state = .error(message); metadata(); return
        }
        state = .connecting; metadata()
        let delay = UInt64(retries * 2) * 1_000_000_000
        retry?.cancel()
        retry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, self.wantsPlayback, !self.interrupted else { return }
            self.startFresh()
        }
    }
    func startMetadata() {
        metadataTask?.cancel()
        if let episode {
            nowPlayingShow = episode.show; nowPlayingTrack = nil
            metadataTask = Task { [weak self] in
                if let url = episode.show.imageURL, let (data, response) = try? await URLSession.shared.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled {
                    self?.showArtwork = UIImage(data: data)
                }
                self?.metadata()
            }
            return
        }
        let id = station.id
        metadataTask = Task { [weak self] in
            while !Task.isCancelled {
                async let show = ProgrammeCache.shared.show(for: id)
                async let track = BBCMetadata.track(for: id)
                let (newShow, newTrack) = await (show, track)
                guard let self, !Task.isCancelled, self.station.id == id else { return }
                self.nowPlayingShow = newShow
                self.nowPlayingTrack = newTrack
                if self.artworkURL != newShow?.imageURL || self.showArtwork == nil {
                    self.artworkURL = newShow?.imageURL
                    self.showArtwork = nil
                    if let url = newShow?.imageURL {
                        var request = URLRequest(url: url); request.timeoutInterval = 12
                        if let (data, response) = try? await URLSession.shared.data(for: request),
                           (response as? HTTPURLResponse)?.statusCode == 200 {
                            guard !Task.isCancelled, self.station.id == id else { return }
                            self.showArtwork = UIImage(data: data)
                        }
                    }
                }
                self.metadata()
                let untilBoundary = self.nowPlayingShow?.end.timeIntervalSinceNow ?? 30
                let delay = max(1, min(30, untilBoundary))
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            }
        }
    }
    private func saveCheckpoint() {
        guard hasPlaybackSession, player.currentItem?.status == .readyToPlay else { return }
        let position = player.currentTime().seconds
        ListeningHistory.shared.save(station: station, programme: episode, position: episode == nil ? 0 : position, duration: episode == nil ? 0 : episodeDuration)
        lastCheckpoint = Date()
    }
    private var activeScenes: Set<UUID> = []
    func setScene(_ id: UUID, active: Bool) {
        if active { ListeningHistory.shared.refresh(); activeScenes.insert(id); startMetadata() }
        else { saveCheckpoint(); activeScenes.remove(id); if activeScenes.isEmpty { stopMetadataIfPaused() } }
    }
    func stopMetadataIfPaused() { if !wantsPlayback { metadataTask?.cancel() } }
    private func donateSuccessfulPlayback() {
        guard pendingDonationStation == station.id else { return }
        pendingDonationStation = nil
        #if os(iOS)
        let intent = INPlayMediaIntent(mediaItems: [station.item], mediaContainer: nil,
                                       playShuffled: nil, playbackRepeatMode: .none,
                                       resumePlayback: nil, playbackQueueLocation: .now,
                                       playbackSpeed: nil, mediaSearch: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { error in
            if let error { NSLog("Sounds Like Siri donation failed: %@", error.localizedDescription) }
        }
        #endif
    }
    private func metadata() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: isRewound ? "Rewound live radio" : (nowPlayingTrack?.title ?? nowPlayingShow?.title ?? station.title),
            MPMediaItemPropertyArtist: isRewound ? station.title : (nowPlayingTrack?.artist ?? station.title),
            MPNowPlayingInfoPropertyIsLiveStream: episode == nil,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPMediaItemPropertyAlbumTitle: station.title
        ]
        if episode != nil {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = episodeDuration
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = episodePosition
        }
        if let artwork = showArtwork {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
    }
}
