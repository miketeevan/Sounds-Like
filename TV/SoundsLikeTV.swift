import SwiftUI
import Combine

@main struct SoundsLikeTVApp: App {
    var body: some Scene { WindowGroup { TVRadioView().onOpenURL { ShelfPublisher.open($0) } } }
}
struct TVRadioView: View {
    @StateObject private var player = RadioPlayer.shared
    @StateObject private var artwork = StationArtworkStore()
    @State private var sceneID = UUID()
    @State private var showingStations = false
    @State private var showingSchedules = false
    @State private var favouritesVisible = true
    @State private var idleTask: Task<Void, Never>?
    private enum FocusTarget: Hashable { case station(String), tile(String), browse, schedules, play, favourite, seek, back, forward, live, retry }
    @FocusState private var focus: FocusTarget?
    @State private var lastTile: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var favourites: [Station] { Station.all.filter { player.favouriteIDs.contains($0.id) } }
    private func recordActivity() {
        idleTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { favouritesVisible = true }
        guard scenePhase == .active, !showingStations, !showingSchedules else { return }
        idleTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, !showingStations, !showingSchedules else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { favouritesVisible = false }
            if case .tile = focus { focus = .play }
            if focus == .browse { focus = .play }
        }
    }
    private func focusFavourites() {
        recordActivity()
        if let station = favourites.first(where: { $0.id == lastTile }) ?? favourites.first { focus = .tile(station.id) }
        else { focus = .browse }
    }
    private func openStations() {
        idleTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showingStations = true }
        focus = .station(Station.all[0].id)
    }
    private func closeStations() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showingStations = false }
        focusFavourites()
    }
    var body: some View {
        shelfContent
            .onReceive(artwork.$entries.debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in ShelfPublisher.update(artwork: artwork) }
            .onReceive(FavouriteStore.shared.$ids.debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in ShelfPublisher.update(artwork: artwork) }
            .onReceive(ListeningHistory.shared.$records.debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in ShelfPublisher.update(artwork: artwork) }
    }
    private var shelfContent: some View {
        GeometryReader { geometry in
            let tileSize = max(120, (geometry.size.height - 32) / 3 - 64)
            ZStack(alignment: .leading) {
                HStack(spacing: favouritesVisible ? 60 : 0) {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(favourites) { station in
                                Button { recordActivity(); player.select(station); focus = .play } label: {
                                    VStack(spacing: 10) {
                                        Group {
                                            if let entry = artwork.entries[station.id], entry.end > Date() {
                                                Image(uiImage: entry.image).resizable().scaledToFill()
                                            } else {
                                                Circle().fill(.teal.opacity(0.15)).overlay(Image(systemName: "radio").font(.largeTitle).foregroundStyle(.teal))
                                            }
                                        }.frame(width: tileSize, height: tileSize).clipShape(Circle())
                                            .overlay(Circle().stroke(focus == .tile(station.id) ? Color.white : (player.station == station ? Color.teal : .clear), lineWidth: 4))
                                        HStack(spacing: 6) {
                                            if player.station == station { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.teal) }
                                            Text(station.title).foregroundStyle(.white)
                                        }.font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
                                            .frame(width: tileSize, height: 48)
                                    }
                                }.buttonStyle(TVFavouriteButtonStyle()).focused($focus, equals: .tile(station.id))
                                    .accessibilityLabel(station.title)
                                    .onMoveCommand { direction in
                                        recordActivity()
                                        if direction == .left { openStations() }
                                        if direction == .right { focus = .play }
                                    }
                            }
                            if favourites.isEmpty {
                                Button("Browse stations") { openStations() }.focused($focus, equals: .browse)
                                    .onMoveCommand { direction in if direction == .left { openStations() }; if direction == .right { focus = .play } }
                                Text("Add favourites to keep them here.").font(.caption)
                            }
                        }.padding(.horizontal, 6)
                    }.frame(width: tileSize + 12)
                        .clipped()
                        .frame(width: favouritesVisible ? tileSize + 12 : 0)
                        .focusSection()
                        .opacity(favouritesVisible ? 1 : 0)
                        .disabled(!favouritesVisible)
                        .accessibilityHidden(!favouritesVisible)
                    VStack(spacing: 20) {
                        Label("SOUNDS LIKE", systemImage: "dot.radiowaves.left.and.right").font(.title2.bold()).foregroundStyle(.teal)
            VStack(spacing: 14) {
                TVProgrammeDial(player: player)
                Text(player.station.title).font(.title2.bold())
                Text(player.nowPlayingShow?.title ?? "Live radio").font(.headline).foregroundStyle(.secondary)
                if !player.isRewound, let track = player.nowPlayingTrack {
                    Text(track.title).font(.title3.bold()).lineLimit(2)
                    Text(track.artist).foregroundStyle(.secondary).lineLimit(1)
                }
                if let window = player.timeline {
                    TVTouchScrubber(position: window.position, lower: window.lower, upper: window.upper,
                                    isEpisode: player.episode != nil, activity: recordActivity,
                                    seek: { player.seek(to: $0) }, toggle: player.toggle)
                        .frame(maxWidth: 900).frame(height: 110)
                        .focused($focus, equals: .seek)
                }
                HStack(spacing: 24) {
                    Button(player.active ? "Pause" : (player.episode == nil ? "Play live" : "Resume episode")) { recordActivity(); player.toggle() }
                        .focused($focus, equals: .play)
                    if player.timeline != nil {
                        Button("Back to live") { recordActivity(); player.backToLive() }.focused($focus, equals: .live)
                    }
                    Button { recordActivity(); player.toggleFavourite(player.station) } label: {
                        Label(player.favouriteIDs.contains(player.station.id) ? "Favourited" : "Favourite", systemImage: player.favouriteIDs.contains(player.station.id) ? "star.fill" : "star")
                    }.focused($focus, equals: .favourite)
                    Button { idleTask?.cancel(); showingSchedules = true } label: {
                        Label("Schedules", systemImage: "calendar")
                    }.focused($focus, equals: .schedules)
                }
                if case .connecting = player.state { ProgressView("Connecting…") }
                if case .error(let error) = player.state { Text(error); Button("Retry") { recordActivity(); player.play() }.focused($focus, equals: .retry) }
            }.frame(maxWidth: .infinity).focusSection()
                .onMoveCommand { direction in
                                        recordActivity()
                    if direction == .left, focus == .play || focus == .back || focus == .retry { focusFavourites() }
                }

                    }
                }.disabled(showingStations)
                if showingStations {
                    Color.black.opacity(0.45).ignoresSafeArea().allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 20) {
                        Text("All BBC stations").font(.title2.bold())
                        Text("Right or Back to return to favourites").font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(Station.all) { station in
                                    Button {
                                        player.select(station)
                                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showingStations = false }
                                        focus = .play
                                    } label: {
                                        HStack(spacing: 16) {
                                            StationProgrammeBadge(station: station, size: 64, artwork: artwork)
                                            Text(station.title).font(.system(size: 24, weight: .semibold)).multilineTextAlignment(.leading).lineLimit(3)
                                            Spacer()
                                            if player.favouriteIDs.contains(station.id) { Image(systemName: "star.fill") }
                                        }.frame(maxWidth: .infinity, minHeight: 72)
                                    }.focused($focus, equals: .station(station.id))
                                }
                            }.padding(12)
                        }
                    }.padding(30).frame(width: 580).background(Color(white: 0.08))
                        .onMoveCommand { direction in if direction == .right { closeStations() } }
                        .onExitCommand { closeStations() }
                        .transition(.move(edge: .leading))
                }
            }
        }.padding(.horizontal, 50).padding(.vertical, 30).background(Color.black).preferredColorScheme(.dark)
            .fullScreenCover(isPresented: $showingSchedules, onDismiss: { focus = .schedules; recordActivity() }) {
                ProgrammeGuide(player: player)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await artwork.preload([player.station] + Station.ordered(favourites: player.favouriteIDs).filter { $0 != player.station })
            }
            .onMoveCommand { _ in recordActivity() }
            .onPlayPauseCommand { recordActivity(); player.toggle() }
            .onChange(of: focus) { _, next in
                if case .tile(let id) = next { lastTile = id }
                // Hiding moves focus to Play; that programmatic move is not remote activity.
                if !favouritesVisible && next == .play { return }
                if next != nil { recordActivity() }
            }
            .onAppear { player.setScene(sceneID, active: true); recordActivity() }
            .onDisappear { idleTask?.cancel(); player.setScene(sceneID, active: false) }
            .onChange(of: scenePhase) { _, phase in
                player.setScene(sceneID, active: phase == .active)
                if phase == .active { recordActivity() } else { idleTask?.cancel() }
            }
    }
}

struct TVProgrammeDial: View {
    @ObservedObject var player: RadioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let show = player.nowPlayingShow.flatMap { player.episode != nil || ($0.start <= context.date && context.date < $0.end) ? $0 : nil }
            let progress = player.episode != nil ? ProgrammeProgress.calculate(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: player.episodeDuration), now: Date(timeIntervalSince1970: player.episodePosition)) : show.flatMap { ProgrammeProgress.calculate(start: $0.start, end: $0.end, now: context.date) }
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.teal.opacity(0.2), lineWidth: 7)
                    if let progress {
                        Circle().trim(from: 0, to: progress.fraction)
                            .stroke(.teal, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .linear(duration: 0.8), value: progress.fraction)
                    }
                    Group {
                        if show != nil, let image = player.showArtwork {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else { StationBadge(station: player.station) }
                    }.frame(width: 272, height: 272).clipShape(Circle())
                }.frame(width: 300, height: 300)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(player.episode == nil ? "Live programme progress" : "Episode progress")
                    .accessibilityValue(progress?.label ?? "Programme timing unavailable")
                if let show, let progress {
                    Text("\(show.start.formatted(date: .omitted, time: .shortened)) – \(show.end.formatted(date: .omitted, time: .shortened)) · \(player.episode == nil ? "LIVE" : "CATCH-UP")")
                        .font(.caption).foregroundStyle(.teal)
                    Text(progress.label).font(.caption).foregroundStyle(.secondary)
                } else { Text("LIVE · Programme timing unavailable").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct TVSchedulesView: View {
    @ObservedObject var player: RadioPlayer
    @State var station: Station
    @State private var date = BroadcastDate.day(Date())
    @State private var items: [ScheduledProgramme] = []
    @State private var loading = true
    @State private var failed = false
    @State private var revision = 0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button("Back to player") { dismiss() }
                Text("Schedules").font(.title.bold())
                Spacer()
                if player.hasPlaybackSession {
                    Text(player.nowPlayingShow?.title ?? player.station.title).lineLimit(1)
                    Button(player.active ? "Pause" : "Resume") { player.toggle() }
                }
            }
            HStack {
                Menu(station.title) {
                    ForEach(Station.ordered(favourites: player.favouriteIDs)) { item in
                        Button(item.title) { station = item }
                    }
                }
                Spacer()
                Button { date = BroadcastDate.adding(-1, to: date) } label: { Label("Previous day", systemImage: "chevron.left") }
                Text(BroadcastDate.label(date)).frame(minWidth: 180)
                Button { date = BroadcastDate.adding(1, to: date) } label: { Label("Next day", systemImage: "chevron.right") }
                Button("Today") { date = BroadcastDate.day(Date()) }
            }.focusSection()
            if loading { ProgressView("Loading schedule…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if failed {
                Text("Couldn’t load the schedule. Your audio is unaffected.")
                Button("Try again") { revision += 1 }
                Spacer()
            } else if items.isEmpty { Text("No schedule published for this date."); Spacer() }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(items) { item in TVScheduleRow(item: item, station: station, player: player).id(item.id) }
                        }.padding(20)
                    }.onAppear { if let current = items.first(where: { $0.isLive(at: Date()) }) { proxy.scrollTo(current.id, anchor: .top) } }
                }.focusSection()
            }
        }.padding(60).background(.black).preferredColorScheme(.dark)
            .onExitCommand { dismiss() }
            .onPlayPauseCommand { player.toggle() }
            .task(id: station.id + BroadcastDate.key(date) + String(revision)) {
                loading = true; failed = false
                do {
                    let rows = try await ScheduleCache.shared.load(station: station.id, day: date, refresh: revision > 0)
                    try Task.checkCancellation(); items = rows; loading = false
                } catch { if !Task.isCancelled { loading = false; failed = true } }
            }
    }
}

private struct TVScheduleRow: View {
    let item: ScheduledProgramme
    let station: Station
    @ObservedObject var player: RadioPlayer
    @State private var playable = false
    @State private var checked = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let live = item.isLive(at: context.date)
            let past = item.show.end <= context.date
            let unavailable = item.unavailable(at: context.date)
            HStack(spacing: 28) {
                ZStack {
                    AsyncImage(url: item.show.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.teal.opacity(0.15) }
                        .frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: live ? 50 : 10))
                    if live, let progress = ProgrammeProgress.calculate(start: item.show.start, end: item.show.end, now: context.date) {
                        Circle().trim(from: 0, to: progress.fraction).stroke(.teal, lineWidth: 4).rotationEffect(.degrees(-90))
                    }
                }.frame(width: 112, height: 112).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(BroadcastDate.time(item.show.start))\(live ? " · LIVE" : "")").foregroundStyle(live ? Color.teal : .secondary)
                    Text(item.show.title).font(.headline)
                    if let subtitle = item.show.subtitle ?? item.show.synopsis { Text(subtitle).font(.caption).lineLimit(2) }
                    Text(ProgrammeProgress.durationLabel(item.show.end.timeIntervalSince(item.show.start))).font(.caption).foregroundStyle(.secondary)
                    if player.active && (player.episode?.id == item.id || (player.episode == nil && player.station == station && live)) { Text("Playing").foregroundStyle(.teal) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if live { Button("Play live") { player.play(station: station) } }
                else if !past { Text("Upcoming").foregroundStyle(.secondary) }
                else if unavailable { Text("Unavailable").foregroundStyle(.secondary) }
                else if playable { Button("Play episode") { player.playEpisode(item, station: station) } }
                else if !checked { ProgressView() }
                else { Text("Listen in BBC Sounds").font(.caption).foregroundStyle(.secondary) }
            }.padding(20).background(live ? Color.teal.opacity(0.1) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                .task(id: past && !unavailable) {
                    guard past, !unavailable else { return }
                    playable = (try? await CatchupResolver.shared.resolve(item)) != nil; checked = true
                }
        }
    }
}

private struct TVFavouriteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// Consume indirect touch movement locally so the focus engine does not turn a
// horizontal scrub into navigation or repeated skip commands.
private struct TVTouchScrubber: UIViewRepresentable {
    let position: Double
    let lower: Double
    let upper: Double
    let isEpisode: Bool
    let activity: () -> Void
    let seek: (Double) -> Void
    let toggle: () -> Void
    func makeUIView(context: Context) -> TVTouchScrubberView { TVTouchScrubberView() }
    func updateUIView(_ view: TVTouchScrubberView, context: Context) {
        view.activity = activity; view.seek = seek; view.toggle = toggle
        view.lower = lower; view.upper = upper; view.isEpisode = isEpisode
        view.position = position
        view.render()
    }
}
private final class TVTouchScrubberView: UIControl, UIGestureRecognizerDelegate {
    var lower = 0.0
    var upper = 1.0
    var position = 0.0
    var isEpisode = false
    var activity: (() -> Void)?
    var seek: ((Double) -> Void)?
    var toggle: (() -> Void)?
    private var editing = false
    private var preview: Double?
    private var startingFraction = 0.0
    private let track = UIView()
    private let fill = UIView()
    private let thumb = UIView()
    private let caption = UILabel()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(scrub(_:)))
    override var canBecomeFocused: Bool { true }
    override init(frame: CGRect) {
        super.init(frame: frame)
        [track, fill, thumb, caption].forEach { addSubview($0) }
        track.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        fill.backgroundColor = .systemTeal; thumb.backgroundColor = .white
        track.layer.cornerRadius = 4; fill.layer.cornerRadius = 4; thumb.layer.cornerRadius = 10
        caption.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        caption.textColor = .lightGray
        caption.textAlignment = .center
        layer.cornerRadius = 12
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.isEnabled = false
        pan.delegate = self
        addGestureRecognizer(pan)
        isAccessibilityElement = true
        accessibilityLabel = "Playback position"
        accessibilityHint = "Press to scrub. Slide to choose a position, press to confirm, or Back to cancel."
        accessibilityTraits = [.adjustable]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); render() }
    func render() {
        let value = preview ?? position
        let fraction = min(1, max(0, (value - lower) / max(1, upper - lower)))
        let width = max(1, bounds.width - 32)
        track.frame = CGRect(x: 16, y: 26, width: width, height: 12)
        fill.frame = CGRect(x: 16, y: 26, width: width * fraction, height: 12)
        thumb.frame = CGRect(x: 16 + (width - 20) * fraction, y: 22, width: 20, height: 20)
        caption.frame = CGRect(x: 12, y: 58, width: bounds.width - 24, height: 32)
        let seconds = max(0, Int(isEpisode ? value : upper - value))
        let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
        caption.text = isEpisode ? time : (seconds < 2 ? "Live" : "−" + time + " behind live")
        accessibilityValue = caption.text
        caption.text = (caption.text ?? "") + (editing ? "   ·   Slide to seek · Press to confirm · Back to cancel" : (isFocused ? "   ·   Press to scrub" : ""))
        backgroundColor = editing ? UIColor.systemTeal.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.04)
        layer.borderWidth = isFocused ? 2 : 0
        layer.borderColor = UIColor.white.cgColor
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: self)
        return isFocused && editing && abs(velocity.x) > abs(velocity.y)
    }
    @objc private func scrub(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            activity?()
            startingFraction = min(1, max(0, ((preview ?? position) - lower) / max(1, upper - lower)))
            preview = preview ?? position
        case .changed:
            activity?()
            let fraction = min(1, max(0, startingFraction + gesture.translation(in: self).x / max(1, (bounds.width - 32) * 6)))
            preview = lower + fraction * (upper - lower)
        case .ended:
            activity?()
        case .cancelled, .failed: break
        default: break
        }
        render()
    }
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        if editing { return false }
        return super.shouldUpdateFocus(in: context)
    }
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        pan.isEnabled = isFocused
        if !isFocused { preview = nil; editing = false }
        render()
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            activity?()
            if editing {
                if let preview { seek?(min(upper, max(lower, preview))) }
                preview = nil; editing = false
            } else { preview = position; editing = true }
            render()
        } else if editing && presses.contains(where: { $0.type == .menu }) {
            preview = nil; editing = false; activity?(); render()
        } else { super.pressesEnded(presses, with: event) }
    }
    override func accessibilityIncrement() { activity?(); seek?(min(upper, position + 5)) }
    override func accessibilityDecrement() { activity?(); seek?(max(lower, position - 5)) }
}
