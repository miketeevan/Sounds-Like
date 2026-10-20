import SwiftUI
import Intents
import AVKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = DownloadLibrary.shared
        _ = ListeningHistory.shared
        #if DOWNLOAD_VERIFICATION
        Task { await DownloadVerification.run() }
        #endif
        let context = INMediaUserContext()
        context.subscriptionStatus = .unknown // This app has no subscription or personal library.
        context.becomeCurrent()
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadLibrary.sessionID else { completionHandler(); return }
        DownloadLibrary.shared.backgroundCompletion = completionHandler
    }
    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        guard let play = intent as? INPlayMediaIntent, let station = Station.resolve(play) else {
            completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil)); return
        }
        RadioPlayer.shared.play(station: station)
        // Accepted for asynchronous playback; the UI reports actual player state.
        completionHandler(INPlayMediaIntentResponse(code: .success, userActivity: nil))
    }
}
@main struct RadioBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { WindowGroup("Sounds Like", id: "player") { AdaptiveRadioRoot() } }
}
private struct WideGuideKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var wideGuide: Bool { get { self[WideGuideKey.self] } set { self[WideGuideKey.self] = newValue } }
}
struct AdaptiveRadioRoot: View {
    @State private var selectedTab = 0
    var body: some View {
        GeometryReader { geometry in
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    VStack(spacing: 0) {
                        VStack(spacing: 12) {
                            HStack { Image(systemName: "dot.radiowaves.left.and.right"); Text("SOUNDS LIKE").tracking(3) }
                                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("Library", selection: $selectedTab) {
                                Text("Listen").tag(0)
                                Text("Downloads").tag(1)
                            }.pickerStyle(.segmented).frame(maxWidth: 360)
                        }.frame(maxWidth: .infinity).padding(12).background(.regularMaterial)
                        if selectedTab == 0 { RadioView(showBranding: false) }
                        else { DownloadsView(player: .shared) }
                    }
                } else {
                    TabView {
                        RadioView().tabItem { Label("Listen", systemImage: "radio") }
                        DownloadsView(player: .shared).tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                    }
                }
            }.environment(\.wideGuide, geometry.size.width >= 700)
                .tint(.teal)
                .modifier(DownloadMessageAlert())
        }
    }
}

struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.tintColor = .label; view.activeTintColor = .systemTeal; return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
struct RadioView: View {
    var showBranding = true
    var body: some View { NavigationStack { RadioPlayerContent(showBranding: showBranding) } }
}

struct RadioPlayerContent: View {
    var showBranding = true
    @Environment(\.wideGuide) private var wideGuide
    @State private var showingGuide = false
    @Environment(\.openWindow) private var openWindow
    @StateObject private var player = RadioPlayer.shared
    @State private var sceneID = UUID()
    @State private var carouselVisible = true
    @State private var expandControls = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var compactControls: Bool { carouselVisible && !expandControls }
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var textSize
    private var inlineControls: Bool { textSize.isAccessibilitySize || verticalSize == .compact }
    @Environment(\.scenePhase) private var scenePhase
    private var status: String {
        switch player.state {
        case .paused: return "Paused"
        case .connecting: return "Connecting…"
        case .playing: return player.episode == nil ? "Playing live" : "Playing episode"
        case .error(let message): return message
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("YOUR STATIONS")
                    .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StationCarousel(player: player)
                    .onGeometryChange(for: Bool.self) { geometry in
                        geometry.frame(in: .named("playerScroll")).maxY > 20
                    } action: { visible in
                        if visible != carouselVisible { carouselVisible = visible; expandControls = false }
                    }
                Group {
                    if wideGuide {
                        Button { showingGuide = true } label: { scheduleButton }
                    } else {
                        NavigationLink { SchedulesView(player: player, station: player.station) } label: { scheduleButton }
                    }
                }.buttonStyle(.plain).accessibilityLabel("Schedules")
                    .accessibilityHint("Browse programmes and catch-up episodes")
                ProgrammeDial(player: player).frame(maxWidth: 560).frame(maxWidth: .infinity)
                if inlineControls { playbackPanel }
                else { Color.clear.frame(height: 230).accessibilityHidden(true) }
            }.padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: .infinity)
        }.coordinateSpace(name: "playerScroll")
            .toolbar {
                if wideGuide {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { openWindow(id: "player") } label: { Label("New window", systemImage: "plus.rectangle.on.rectangle") }
                    }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { gesture in
                guard abs(gesture.translation.height) > abs(gesture.translation.width) else { return }
                if gesture.translation.height < -8 { expandControls = true }
                if gesture.translation.height > 8 && carouselVisible { expandControls = false }
            })
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                if showBranding {
                HStack { Image(systemName: "dot.radiowaves.left.and.right"); Text("SOUNDS LIKE").tracking(3) }
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !inlineControls {
                    // Keep the scroll viewport stable while the panel slides over it.
                    Color.clear.frame(height: 64)
                        .overlay(alignment: .bottom) {
                            currentPlaybackPanel
                                .fixedSize(horizontal: false, vertical: true)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: compactControls)
                        }
                }
            }
            .fullScreenCover(isPresented: $showingGuide) {
                GeometryReader { geometry in
                    if geometry.size.width >= 700 { ProgrammeGuide(player: player) }
                    else {
                        NavigationStack {
                            SchedulesView(player: player, station: player.station)
                                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Player") { showingGuide = false } } }
                        }
                    }
                }
            }
            .onAppear { player.setScene(sceneID, active: true) }
            .onDisappear { player.setScene(sceneID, active: false) }
            .onChange(of: scenePhase) { _, phase in
                player.setScene(sceneID, active: phase == .active)
            }
    }
    private var scheduleButton: some View {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.title3.weight(.semibold)).foregroundStyle(.teal)
                            .frame(width: 40, height: 40)
                            .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        Text("Schedules").font(.headline).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.teal.opacity(0.22), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 20))

    }
    @ViewBuilder private var currentPlaybackPanel: some View {
        if compactControls {
            HStack(spacing: 8) {
                Button(action: player.toggle) {
                    Image(systemName: player.active ? "pause.fill" : "play.fill")
                        .font(.title3.bold()).frame(width: 44, height: 44)
                        .foregroundStyle(.white).background(.teal, in: Circle())
                }.accessibilityLabel(player.active ? "Pause" : (player.episode == nil ? "Play live" : "Resume episode"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.isRewound ? player.station.title : (player.nowPlayingTrack?.title ?? player.nowPlayingShow?.title ?? player.station.title))
                        .font(.subheadline.bold()).lineLimit(1)
                    Text(player.isRewound ? "Behind live" : (player.nowPlayingTrack?.artist ?? status))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                AirPlayPicker().frame(width: 48, height: 44)
                    .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }.padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial)
                .transition(.opacity)
        } else {
            playbackPanel.transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    private var playbackPanel: some View {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.isRewound ? "BEHIND LIVE" : "NOW PLAYING")
                            .font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.teal)
                        if let episode = player.episode {
                            Text(episode.show.title).font(.title2.bold())
                            Text(episode.show.subtitle ?? player.station.title).font(.subheadline).foregroundStyle(.secondary)
                        } else if !player.isRewound, let track = player.nowPlayingTrack {
                            Text(track.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                            Text(track.artist).font(.body.weight(.medium)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(player.station.title).font(.headline)
                            Text(player.isRewound ? "Track details unavailable for rewound audio" : "Waiting for track information")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    TimelineControls(player: player)
                    HStack(spacing: 16) {
                        Button(action: player.toggle) {
                            Image(systemName: player.active ? "pause.fill" : "play.fill")
                                .font(.system(size: 21, weight: .bold))
                                .frame(width: 52, height: 52)
                                .foregroundStyle(.white).background(.teal, in: Circle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(player.active ? "Pause" : (player.episode == nil ? "Play live" : "Resume episode"))
                        Text(status).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Playback status: \(status)")
                        VStack(spacing: 0) {
                            AirPlayPicker().frame(width: 72, height: 44)
                            Text("AirPlay").font(.caption.weight(.bold)).padding(.bottom, 6)
                        }.background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if case .error = player.state { Button("Retry live stream", action: player.play).buttonStyle(.bordered) }
                }.padding(.horizontal, 24).padding(.vertical, 12).background(.regularMaterial)
    }
}

struct StationPicker: View {
    @ObservedObject var player: RadioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var matchingStations: [Station] {
        Station.all.filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.aliases.contains { $0.localizedStandardContains(query) }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                let favourites = matchingStations.filter { player.favouriteIDs.contains($0.id) }
                if !favourites.isEmpty {
                    Section("Favourites") {
                        ForEach(favourites) { station in stationRow(station) }
                    }
                } else if query.isEmpty && player.favouriteIDs.isEmpty {
                    Section("Favourites") {
                        Text("Tap a star to keep your favourite stations here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ForEach(Station.groups, id: \.self) { group in
                    let stations = matchingStations.filter { $0.group == group && !player.favouriteIDs.contains($0.id) }
                    if !stations.isEmpty {
                        Section(group) {
                            ForEach(stations) { station in stationRow(station) }
                        }
                    }
                }
                if matchingStations.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }.navigationTitle("BBC stations").searchable(text: $query, prompt: "Find a station")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func stationRow(_ station: Station) -> some View {
        HStack(spacing: 12) {
            Button {
                player.select(station); dismiss()
            } label: {
                HStack {
                    Text(station.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Spacer()
                    if player.station == station { Image(systemName: "checkmark").foregroundStyle(.teal) }
                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityAddTraits(player.station == station ? .isSelected : [])
            Button {
                player.toggleFavourite(station)
            } label: {
                Image(systemName: player.favouriteIDs.contains(station.id) ? "star.fill" : "star")
                    .foregroundStyle(player.favouriteIDs.contains(station.id) ? Color.orange : Color.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.borderless)
                .accessibilityLabel("\(player.favouriteIDs.contains(station.id) ? "Remove" : "Add") \(station.title) \(player.favouriteIDs.contains(station.id) ? "from" : "to") favourites")
        }
    }
}

struct TimelineControls: View {
    @ObservedObject var player: RadioPlayer
    var showTransportButtons = true
    @State private var dragging = false
    @State private var fraction = 1.0
    private func time(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    var body: some View {
        if let window = player.timeline {
            VStack(spacing: 4) {
                Slider(value: Binding(get: {
                    dragging ? fraction : min(1, max(0, (window.position - window.lower) / window.duration))
                }, set: { value in
                    fraction = value
                    // VoiceOver adjustments may not produce a drag gesture.
                    if !dragging { player.seek(to: window.lower + value * window.duration) }
                }), in: 0...1, onEditingChanged: { editing in
                    if editing { fraction = min(1, max(0, (window.position - window.lower) / window.duration)) }
                    dragging = editing
                    if !editing { player.seek(to: window.lower + fraction * window.duration) }
                })
                .tint(.teal).accessibilityLabel(player.episode == nil ? "Rewind within available live show" : "Episode position")
                .accessibilityValue(player.episode != nil ? time(window.position) : (player.isRewound ? "\(time(window.behindLive)) behind live" : "Live"))
                if showTransportButtons {
                HStack {
                    Button { player.skip(-30) } label: { Image(systemName: "gobackward.30") }
                        .accessibilityLabel("Back 30 seconds").frame(minWidth: 44, minHeight: 44)
                    Text(player.episode != nil ? time(window.position) : (player.isRewound ? "−\(time(window.behindLive))" : "Live")).font(.caption.monospacedDigit())
                    Button { player.skip(30) } label: { Image(systemName: "goforward.30") }
                        .accessibilityLabel("Forward 30 seconds").frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button("Back to live", action: player.backToLive).font(.subheadline.weight(.semibold))
                }
                }
                if let error = player.seekError { Text(error).font(.caption).foregroundStyle(.red) }
            }
        } else if player.active {
            Text("Rewind becomes available when the stream provides a seekable window.").font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct StationCarousel: View {
    @StateObject private var artwork = StationArtworkStore()
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var player: RadioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var badgeSize = 104.0
    @Environment(\.dynamicTypeSize) private var carouselTextSize
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Station.ordered(favourites: player.favouriteIDs)) { station in
                        Button { player.select(station); player.play() } label: {
                            VStack(spacing: 8) {
                                StationProgrammeBadge(station: station, size: badgeSize, artwork: artwork).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    .padding(5)
                                    .overlay(Circle().stroke(player.station == station ? Color.teal : .clear, lineWidth: 3))
                                    .overlay(alignment: .bottomTrailing) {
                                        if player.favouriteIDs.contains(station.id) {
                                            Image(systemName: "star.fill").font(.caption2.bold()).foregroundStyle(.orange)
                                                .padding(4).background(.background, in: Circle())
                                        }
                                    }
                                Text(station.shortTitle).font(.caption).multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                                    .foregroundStyle(player.station == station ? .primary : .secondary)
                            }.frame(width: badgeSize + 14)
                        }.buttonStyle(.plain).id(station.id)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(station.title)
                            .accessibilityHint("Plays this station live")
                            .accessibilityValue(player.favouriteIDs.contains(station.id) ? "Favourite" : "")
                            .accessibilityAddTraits(player.station == station ? .isSelected : [])
                    }
                }.padding(.vertical, 5).padding(.horizontal, 3)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                let stations = [player.station] + Station.ordered(favourites: player.favouriteIDs).filter { $0 != player.station }
                await artwork.preload(stations)
            }
            .onAppear { proxy.scrollTo(player.station.id, anchor: .center) }
            .onChange(of: carouselTextSize) { _, _ in proxy.scrollTo(player.station.id, anchor: .center) }
            .onChange(of: player.station.id) { _, id in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: player.favouriteIDs) { _, _ in
                proxy.scrollTo(player.station.id, anchor: .center)
            }
        }
    }
}

struct ProgrammeDial: View {
    @ObservedObject var player: RadioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let show = player.nowPlayingShow.flatMap { player.episode != nil || ($0.start <= context.date && context.date < $0.end) ? $0 : nil }
            let progress = player.episode != nil ? ProgrammeProgress.calculate(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: player.episodeDuration), now: Date(timeIntervalSince1970: player.episodePosition)) : show.flatMap { ProgrammeProgress.calculate(start: $0.start, end: $0.end, now: context.date) }
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.teal.opacity(0.13), lineWidth: 7)
                    if let progress {
                        Circle().trim(from: 0, to: progress.fraction)
                            .stroke(.teal, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .linear(duration: 0.8), value: progress.fraction)
                    }
                    Group {
                        if show != nil, let artwork = player.showArtwork {
                            Image(uiImage: artwork).resizable().scaledToFill()
                        } else {
                            StationBadge(station: player.station)
                        }
                    }.clipShape(Circle()).padding(14)
                }.aspectRatio(1, contentMode: .fit).frame(maxWidth: 250)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(player.episode == nil ? "Live programme progress" : "Episode playback progress")
                    .accessibilityValue(progress?.label ?? "Programme timing unavailable")
                    .accessibilityHint(player.episode == nil ? "Shows broadcast progress" : "Shows playback position")
                HStack(alignment: .center, spacing: 12) {
                    Text(player.station.title).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    Button { player.toggleFavourite(player.station) } label: {
                        Image(systemName: player.favouriteIDs.contains(player.station.id) ? "star.fill" : "star")
                            .font(.title2).foregroundStyle(.teal).frame(width: 48, height: 48)
                    }.accessibilityLabel(player.favouriteIDs.contains(player.station.id) ? "Remove selected station from favourites" : "Add selected station to favourites")
                }
                Label(player.episode == nil ? "LIVE" : "CATCH-UP", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.teal)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(.teal.opacity(0.1), in: Capsule())
                if let show {
                    Text(show.title).font(.title2.bold()).multilineTextAlignment(.center)
                    if let subtitle = show.subtitle, subtitle != show.title {
                        Text(subtitle).font(.headline).multilineTextAlignment(.center)
                    }
                    Text("\(show.start.formatted(date: .omitted, time: .shortened)) – \(show.end.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    if let progress { Text(progress.label).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    if let synopsis = show.synopsis {
                        Text(synopsis).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                } else {
                    Text("\(player.station.title) live").font(.title2.bold()).multilineTextAlignment(.center)
                    Text("Programme details are currently unavailable.").font(.subheadline).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity)
        }
    }
}


struct SchedulesView: View {
    @State private var searchText = ""
    @ObservedObject var player: RadioPlayer
    @State var station: Station
    @State private var date = BroadcastDate.day(Date())
    @State private var days = (-7...7).map { BroadcastDate.adding($0, to: BroadcastDate.day(Date())) }
    @State private var programmes: [ScheduledProgramme] = []
    @State private var loading = true
    @State private var error: String?
    @State private var refresh = 0
    @State private var sceneID = UUID()
    @StateObject private var artwork = StationArtworkStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private var selection: String { station.id + BroadcastDate.key(date) + String(refresh) }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Station.ordered(favourites: player.favouriteIDs)) { item in
                            Button { station = item } label: {
                                VStack {
                                    StationProgrammeBadge(station: item, size: 64, artwork: artwork)
                                        .overlay(Circle().stroke(station == item ? Color.teal : .clear, lineWidth: 3))
                                    Text(item.title).font(.caption).lineLimit(3).frame(width: 88)
                                }
                            }.buttonStyle(.plain).id(item.id)
                                .accessibilityLabel(item.title).accessibilityAddTraits(station == item ? .isSelected : [])
                        }
                    }.padding()
                }.onAppear { proxy.scrollTo(station.id, anchor: .center) }
                    .onChange(of: station.id) { _, id in proxy.scrollTo(id, anchor: .center) }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        Button("Earlier") { let first = days.first!; days.insert(contentsOf: (-7 ... -1).map { BroadcastDate.adding($0, to: first) }, at: 0); date = BroadcastDate.adding(-1, to: first) }
                        ForEach(days, id: \.self) { day in
                            Button { date = day } label: {
                                VStack(spacing: 8) {
                                    Text(BroadcastDate.label(day)).font(.subheadline.weight(.semibold))
                                    Rectangle().fill(day == date ? Color.teal : .clear).frame(height: 3)
                                }.foregroundStyle(day == date ? Color.teal : Color.primary)
                            }.id(day).accessibilityAddTraits(day == date ? .isSelected : [])
                        }
                        Button("Later") { let last = days.last!; days += (1...7).map { BroadcastDate.adding($0, to: last) }; date = BroadcastDate.adding(1, to: last) }
                    }.padding(.horizontal)
                }.onAppear { proxy.scrollTo(date, anchor: .center) }
                    .onChange(of: date) { _, value in proxy.scrollTo(value, anchor: .center) }
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if loading { ProgressView("Loading schedule…").padding(40) }
                        else if let error {
                            ContentUnavailableView { Label("Schedule unavailable", systemImage: "wifi.exclamationmark") } description: { Text(error) } actions: { Button("Try again") { refresh += 1 } }
                        } else if programmes.isEmpty {
                            ContentUnavailableView("No schedule published", systemImage: "calendar", description: Text("The BBC has no listings for this station and date. Try another day."))
                        } else {
                            if !searchText.isEmpty && !programmes.contains(where: { $0.matchesScheduleSearch(searchText, station: station) }) {
                                ContentUnavailableView("No matching programmes", systemImage: "magnifyingglass", description: Text("Try another search or date."))
                            }
                            ForEach(programmes.filter { $0.matchesScheduleSearch(searchText, station: station) }) { programme in
                                ScheduleRow(programme: programme, station: station, player: player).id(programme.id)
                                Divider().padding(.horizontal)
                            }
                        }
                    }
                }.refreshable { refresh += 1 }
                    .task(id: selection) {
                        loading = true; error = nil; programmes = []
                        do {
                            let items = try await ScheduleCache.shared.load(station: station.id, day: date, refresh: refresh > 0)
                            try Task.checkCancellation(); programmes = items; loading = false
                            await Task.yield()
                            if let current = items.first(where: { $0.isLive(at: Date()) }) { proxy.scrollTo(current.id, anchor: .top) }
                        } catch is CancellationError { }
                        catch { if !Task.isCancelled { self.error = "Couldn’t load the BBC schedule. Your audio is unaffected."; loading = false } }
                    }
            }
        }
        .task(id: station.id + BroadcastDate.key(date)) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(300))
                    let latest = try await ScheduleCache.shared.load(station: station.id, day: date, refresh: true)
                    try Task.checkCancellation(); programmes = latest
                } catch { if Task.isCancelled { return } }
            }
        }
        .modifier(ScheduleSearchControl(query: $searchText))
        .navigationTitle(station.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    StationProgrammeBadge(station: player.station, size: 36, artwork: artwork)
                        .frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Return to Now Playing")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.hasPlaybackSession {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        HStack {
                            Group { if let image = player.showArtwork { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "radio").resizable().scaledToFit() } }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(player.nowPlayingShow?.title ?? player.station.title).font(.subheadline.bold()).lineLimit(1)
                                Text("\(player.station.title) · \(playbackStatus)").font(.caption).lineLimit(2)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Return to player. \(player.nowPlayingShow?.title ?? player.station.title)")
                    Button(action: player.toggle) { Image(systemName: player.active ? "pause.fill" : "play.fill").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel(player.active ? "Pause" : "Resume")
                }.padding().background(.regularMaterial)
            }
        }
        .task(id: scenePhase) { if scenePhase == .active { await artwork.preload([station] + Station.ordered(favourites: player.favouriteIDs).filter { $0 != station }) } }
        .onAppear { player.setScene(sceneID, active: true) }
        .onDisappear { player.setScene(sceneID, active: false) }
        .onChange(of: scenePhase) { _, phase in player.setScene(sceneID, active: phase == .active) }
    }
    private var playbackStatus: String {
        switch player.state { case .paused: return "Paused"; case .connecting: return "Connecting"; case .error: return "Playback unavailable"; case .playing: return player.episode == nil ? "Live" : "Catch-up" }
    }
}

private struct ScheduleRow: View {
    let programme: ScheduledProgramme
    let station: Station
    @ObservedObject var player: RadioPlayer
    @State private var playable = false
    @State private var checking = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let live = programme.isLive(at: context.date)
            let past = programme.show.end <= context.date
            let unavailable = programme.unavailable(at: context.date)
            let playing = player.active && (player.episode?.id == programme.id || (player.episode == nil && player.station == station && live))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    artwork(live: live, now: context.date)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(BroadcastDate.time(programme.show.start) + (live ? " · LIVE" : "")).font(.subheadline.bold()).foregroundStyle(live ? Color.teal : Color.secondary)
                        Text(programme.show.title).font(.headline)
                        if let subtitle = programme.show.subtitle ?? programme.show.synopsis { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                        Text(ProgrammeProgress.durationLabel(programme.show.end.timeIntervalSince(programme.show.start))).font(.caption).foregroundStyle(.secondary)
                        if playing { Label("Playing", systemImage: "speaker.wave.2.fill").font(.caption.bold()).foregroundStyle(.teal) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer(minLength: 0)
                    if live {
                        Button { player.play(station: station) } label: { Label("Play live", systemImage: "play.fill") }
                    } else if !past { Text("Upcoming · \(BroadcastDate.label(programme.show.start)) \(BroadcastDate.time(programme.show.start))").foregroundStyle(.secondary) }
                    else if unavailable { Text("No longer available").foregroundStyle(.secondary) }
                    else if playable {
                        Button { player.playEpisode(programme, station: station) } label: { Label("Play episode", systemImage: "play.fill") }
                    } else if checking { ProgressView("Checking playback…") }
                    else if let url = programme.soundsURL { Link("Open in BBC Sounds", destination: url) }
                    else { Text("Playback unavailable").foregroundStyle(.secondary) }
                }.font(.subheadline).frame(minHeight: 44)
            }.padding().background(live ? Color.teal.opacity(0.07) : .clear)
                .contextMenu { DownloadMenu(programme: programme, station: station) }
                .task(id: past && !unavailable) {
                    guard past, !unavailable else { playable = false; return }
                    checking = true
                    playable = (try? await CatchupResolver.shared.resolve(programme)) != nil
                    checking = false
                }
        }
    }
    private func artwork(live: Bool, now: Date) -> some View {
        ZStack {
            AsyncImage(url: programme.show.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15).overlay(Image(systemName: "radio")) }
                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: live ? 36 : 6))
            if live, let progress = ProgrammeProgress.calculate(start: programme.show.start, end: programme.show.end, now: now) {
                Circle().stroke(.teal.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: progress.fraction).stroke(.teal, lineWidth: 3).rotationEffect(.degrees(-90))
            }
        }.frame(width: 80, height: 80).accessibilityHidden(true)
    }
}
