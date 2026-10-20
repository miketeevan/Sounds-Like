import SwiftUI

private struct GuideOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ProgrammeGuide: View {
    @ObservedObject var player: RadioPlayer
    @State private var searchText = ""
    @State private var searchItems: [String: [ScheduledProgramme]] = [:]
    @State private var searchLoading = false
    @State private var searchFailures = 0
    @State private var date = BroadcastDate.day(Date())
    @State private var horizontalOffset: CGFloat = 0
    @State private var lastActivatedProgramme: String?
    @State private var selected: ScheduledProgramme?
    @State private var selectedStation: Station?
    @State private var playable = false
    @State private var checking = false
    @State private var sceneID = UUID()
    @StateObject private var artwork = StationArtworkStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedProgramme: String?
    #if os(tvOS)
    private let stationWidth: CGFloat = 240
    private let rowHeight: CGFloat = 105
    private let hourWidth: CGFloat = 270
    #else
    private let stationWidth: CGFloat = 172
    private let rowHeight: CGFloat = 96
    private let hourWidth: CGFloat = 220
    #endif
    private var stations: [Station] { Station.ordered(favourites: player.favouriteIDs) }
    private var end: Date { BroadcastDate.adding(1, to: date) }
    private var hours: Int { Int(end.timeIntervalSince(date) / 3600) }
    private var timelineWidth: CGFloat { CGFloat(hours) * hourWidth }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Button { dismiss() } label: { Label("Player", systemImage: "chevron.left") }
                Text("Schedules").font(.title2.bold())
                Spacer()
                Button { changeDay(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Previous day")
                Text(BroadcastDate.label(date)).font(.headline).frame(minWidth: 120)
                Button { changeDay(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Next day")
                Button("Today") { date = BroadcastDate.day(Date()); selected = nil }
            }
            preview
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { searchResults } else {
            #if os(tvOS)
            TVNativeGuide(playerStation: player.station, stations: stations, date: date, select: { programme, station in
                selected = programme; selectedStation = station
            }, activate: { programme, station in
                playProgramme(programme, station: station)
            })
            #else
            grid
            #endif
            }
            if player.hasPlaybackSession {
                VStack(spacing: 8) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.teal)
                    Text(player.nowPlayingShow?.title ?? player.station.title).font(.headline).lineLimit(1)
                    Text(player.station.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(player.active ? "Pause" : "Resume", action: player.toggle)
                }
                #if os(iOS)
                TimelineControls(player: player)
                #endif
                }.padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }.padding(guidePadding).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark)
            .modifier(ScheduleSearchControl(query: $searchText))
            .task(id: BroadcastDate.key(date) + String(!searchText.isEmpty)) {
                guard !searchText.isEmpty else { return }
                searchLoading = true; searchItems = [:]; searchFailures = 0
                for start in stride(from: 0, to: stations.count, by: 8) {
                    guard !Task.isCancelled else { return }
                    let batch = Array(stations[start..<min(start + 8, stations.count)])
                    await withTaskGroup(of: (String, [ScheduledProgramme]?).self) { group in
                        for station in batch {
                            group.addTask { (station.id, try? await ScheduleCache.shared.load(station: station.id, day: date)) }
                        }
                        for await (id, items) in group {
                            guard !Task.isCancelled else { continue }
                            if let items { searchItems[id] = items } else { searchFailures += 1 }
                        }
                    }
                }
                if !Task.isCancelled { searchLoading = false }
            }
            .task(id: scenePhase) {
                #if os(iOS)
                if scenePhase == .active { await artwork.preload([player.station] + stations.filter { $0 != player.station }) }
                #endif
            }
            .task(id: selected?.id) {
                playable = false; checking = false
                guard let selected, selected.show.end <= Date(), !selected.unavailable(at: Date()) else { return }
                checking = true
                let resolved = (try? await CatchupResolver.shared.resolve(selected)) != nil
                guard !Task.isCancelled else { return }
                playable = resolved; checking = false
            }
            .onAppear { player.setScene(sceneID, active: true) }
            .onDisappear { player.setScene(sceneID, active: false) }
            .onChange(of: scenePhase) { _, phase in player.setScene(sceneID, active: phase == .active) }
            #if os(tvOS)
            .ignoresSafeArea()
            .onExitCommand { dismiss() }
            .onPlayPauseCommand { player.toggle() }
            #endif
    }
    private var searchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if searchLoading { ProgressView("Searching this day's schedules…") }
                if searchFailures > 0 { Text("Some station schedules could not be loaded.").font(.caption).foregroundStyle(.secondary) }
                let matches = stations.flatMap { station in
                    (searchItems[station.id] ?? []).filter { $0.matchesScheduleSearch(searchText, station: station) }.map { (station, $0) }
                }
                if matches.isEmpty && !searchLoading {
                    Text("No matching programmes for this day.").foregroundStyle(.secondary).padding()
                }
                ForEach(matches, id: \.1.id) { station, programme in
                    Button { playProgramme(programme, station: station) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(programme.show.title).font(.headline)
                                Text(station.title + " · " + BroadcastDate.time(programme.show.start)).font(.subheadline).foregroundStyle(.secondary)
                                if let subtitle = programme.show.subtitle { Text(subtitle).font(.caption).lineLimit(2) }
                            }
                            Spacer()
                            Image(systemName: "play.circle")
                        }.padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                    #if os(iOS)
                    .contextMenu { DownloadMenu(programme: programme, station: station) }
                    #endif
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var guidePadding: CGFloat {
        #if os(tvOS)
        24
        #else
        20
        #endif
    }
    private func playProgramme(_ programme: ScheduledProgramme, station: Station) {
        selected = programme; selectedStation = station
        let now = Date()
        let key = station.id + ":" + programme.id
        let isCurrentPlayback = player.station == station &&
            (player.episode?.id == programme.id || (player.episode == nil && programme.isLive(at: now)))
        if lastActivatedProgramme == key, isCurrentPlayback, player.active {
            dismiss()
            return
        }
        if programme.isLive(at: now) {
            lastActivatedProgramme = key
            player.play(station: station)
        } else if programme.show.end <= now, !programme.unavailable(at: now) {
            lastActivatedProgramme = key
            player.playEpisode(programme, station: station)
        }
    }
    private func changeDay(_ offset: Int) { date = BroadcastDate.adding(offset, to: date); selected = nil }
    private var preview: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(alignment: .center, spacing: 22) {
                #if os(iOS)
                Button { dismiss() } label: {
                AsyncImage(url: selected?.show.imageURL) { image in image.resizable().scaledToFill() } placeholder: {
                    Color.teal.opacity(0.12).overlay(Image(systemName: "radio").font(.largeTitle).foregroundStyle(.teal))
                }.frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityLabel("Return to Now Playing")
                #else
                AsyncImage(url: selected?.show.imageURL) { image in image.resizable().scaledToFill() } placeholder: {
                    Color.teal.opacity(0.12).overlay(Image(systemName: "radio").font(.largeTitle).foregroundStyle(.teal))
                }.frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                #endif
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(selectedStation?.title ?? "SOUNDS LIKE").font(.caption.bold()).foregroundStyle(.teal)
                        if let station = selectedStation {
                            Button { player.toggleFavourite(station) } label: {
                                Image(systemName: player.favouriteIDs.contains(station.id) ? "star.fill" : "star")
                                    .foregroundStyle(.teal).frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(player.favouriteIDs.contains(station.id) ? "Remove \(station.title) from favourites" : "Add \(station.title) to favourites")
                        }
                    }
                    Text(selected?.show.title ?? "Choose a programme").font(.title2.bold()).lineLimit(2)
                    Text(selected?.show.subtitle ?? selected?.show.synopsis ?? "Browse stations vertically and programmes across the timeline.").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    if let selected {
                        Text("\(BroadcastDate.time(selected.show.start)) – \(BroadcastDate.time(selected.show.end)) · \(ProgrammeProgress.durationLabel(selected.show.end.timeIntervalSince(selected.show.start)))").font(.caption)
                        #if os(iOS)
                        if player.hasPlaybackSession, selectedStation == player.station,
                           player.episode?.id == selected.id || (player.episode == nil && selected.isLive(at: context.date)) {
                            TimelineControls(player: player, showTransportButtons: false)
                        } else if selected.isLive(at: context.date), let progress = ProgrammeProgress.calculate(start: selected.show.start, end: selected.show.end, now: context.date) {
                            ProgressView(value: progress.fraction).tint(.teal).accessibilityLabel("Live programme progress")
                        }
                        #else
                        if selected.isLive(at: context.date), let progress = ProgrammeProgress.calculate(start: selected.show.start, end: selected.show.end, now: context.date) {
                            ProgressView(value: progress.fraction).tint(.teal).accessibilityLabel("Live programme progress")
                        }
                        #endif
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let selected, let station = selectedStation {
                    if selected.isLive(at: context.date) { Button("Play live") { player.play(station: station) } }
                    else if selected.show.start > context.date { Text("Upcoming").foregroundStyle(.secondary) }
                    else if selected.unavailable(at: context.date) { Text("Unavailable").foregroundStyle(.secondary) }
                    else if checking { ProgressView() }
                    else if playable { Button("Play episode") { player.playEpisode(selected, station: station) } }
                    else {
                        #if os(iOS)
                        if let url = selected.soundsURL { Link("Open in BBC Sounds", destination: url) }
                        #else
                        Text("Unavailable in app").font(.caption).foregroundStyle(.secondary)
                        #endif
                    }
                }
            }.padding(18).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
                #if os(iOS)
                .contextMenu { if let selected, let station = selectedStation { DownloadMenu(programme: selected, station: station) } }
                #endif
        }
    }
    private var grid: some View {
        GeometryReader { viewport in
            ScrollViewReader { horizontal in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        ruler
                        ScrollViewReader { vertical in
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 1) {
                                    ForEach(stations) { station in
                                        GuideStationRow(station: station, date: date, dayEnd: end, stationWidth: stationWidth, rowHeight: rowHeight, hourWidth: hourWidth, horizontalOffset: horizontalOffset, artwork: artwork, selectedID: selected?.id, focusedProgramme: $focusedProgramme) { programme in
                                            playProgramme(programme, station: station)
                                        } loaded: { programmes in
                                            if selected == nil, station == player.station, let current = programmes.first(where: { $0.isLive(at: Date()) }) { selected = current; selectedStation = station }
                                        }.id(station.id)
                                    }
                                }
                            }.onAppear { vertical.scrollTo(player.station.id, anchor: .top) }
                        }
                    }.frame(width: timelineWidth + stationWidth, height: viewport.size.height)
                        .background(GeometryReader { position in Color.clear.preference(key: GuideOffsetKey.self, value: -position.frame(in: .named("guideHorizontal")).minX) })
                }.guideHorizontalOffset($horizontalOffset).coordinateSpace(name: "guideHorizontal")
                    .onPreferenceChange(GuideOffsetKey.self) {
                        if #available(iOS 18.0, tvOS 18.0, *) { } else { horizontalOffset = max(0, $0) }
                    }
                    .task(id: date) {
                        await Task.yield()
                        let hour = BroadcastDate.day(Date()) == date ? max(0, Int(Date().timeIntervalSince(date) / 3600) - 1) : 0
                        horizontal.scrollTo("hour-\(hour)", anchor: .leading)
                    }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private var ruler: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: stationWidth)
                ForEach(0..<hours, id: \.self) { hour in
                    Text(BroadcastDate.time(date.addingTimeInterval(Double(hour) * 3600)))
                        .font(.caption.bold()).frame(width: hourWidth, height: 44, alignment: .leading).id("hour-\(hour)")
                }
            }
            Text("STATIONS").font(.caption.bold()).foregroundStyle(.teal)
                .frame(width: stationWidth, height: 44, alignment: .leading).background(Color(white: 0.07)).offset(x: horizontalOffset)
        }.frame(height: 44).background(Color(white: 0.07))
    }
}

private struct GuideStationRow: View {
    let station: Station
    let date: Date
    let dayEnd: Date
    let stationWidth: CGFloat
    let rowHeight: CGFloat
    let hourWidth: CGFloat
    let horizontalOffset: CGFloat
    @ObservedObject var artwork: StationArtworkStore
    let selectedID: String?
    var focusedProgramme: FocusState<String?>.Binding
    let select: (ScheduledProgramme) -> Void
    let loaded: ([ScheduledProgramme]) -> Void
    @State private var items: [ScheduledProgramme] = []
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    private var width: CGFloat { CGFloat(dayEnd.timeIntervalSince(date) / 3600) * hourWidth + stationWidth }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack(alignment: .leading) {
                Color.white.opacity(0.025)
                if loading || failed || items.isEmpty {
                    HStack {
                        if loading { ProgressView() }
                        else if failed { Button("Retry schedule") { retry += 1 } }
                        else { Text("No schedule published").font(.caption).foregroundStyle(.secondary) }
                    }.offset(x: horizontalOffset + stationWidth + 16)
                }
                ForEach(items) { item in
                    programmeCell(item, now: context.date)
                }
                if date <= context.date, context.date < dayEnd {
                    Rectangle().fill(.teal).frame(width: 2, height: rowHeight)
                        .offset(x: stationWidth + CGFloat(context.date.timeIntervalSince(date) / 3600) * hourWidth).allowsHitTesting(false)
                }
                HStack(spacing: 10) {
                    StationProgrammeBadge(station: station, size: 44, artwork: artwork)
                    Text(station.title).font(.caption.weight(.semibold)).lineLimit(3)
                }.padding(.horizontal, 10).frame(width: stationWidth, height: rowHeight, alignment: .leading)
                    .background(Color(white: 0.08)).offset(x: horizontalOffset).zIndex(2)
            }.frame(width: width, height: rowHeight)
        }.task(id: station.id + BroadcastDate.key(date) + String(retry)) {
            loading = true; failed = false; items = []
            do {
                let response = try await ScheduleCache.shared.load(station: station.id, day: date, refresh: retry > 0)
                try Task.checkCancellation(); items = response; loading = false; loaded(response)
            } catch { if !Task.isCancelled { loading = false; failed = true } }
        }
    }
    @ViewBuilder private func programmeCell(_ item: ScheduledProgramme, now: Date) -> some View {
                    let start = max(date, item.show.start)
                    let finish = min(dayEnd, item.show.end)
                    if finish > start {
                        let cellWidth = CGFloat(finish.timeIntervalSince(start) / 3600) * hourWidth
                        let startX: CGFloat = CGFloat(start.timeIntervalSince(date) / 3600) * hourWidth
                        let obscured: CGFloat = max(CGFloat.zero, horizontalOffset - startX)
                        let hiddenLeading: CGFloat = min(max(CGFloat.zero, cellWidth - 4), obscured)
                        let border: Color = focusedProgramme.wrappedValue == item.id ? .white : (selectedID == item.id ? .teal : .white.opacity(0.13))
                        Button { select(item) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(BroadcastDate.time(item.show.start) + (item.isLive(at: now) ? " · LIVE" : "")).font(.caption2.bold()).foregroundStyle(.teal)
                                Text(item.show.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            }.padding(10).frame(width: max(1, cellWidth - 4 - hiddenLeading), height: rowHeight - 8, alignment: .topLeading)
                                .padding(.leading, hiddenLeading)
                                .frame(width: max(1, cellWidth - 4), height: rowHeight - 8, alignment: .leading)
                                .background(item.isLive(at: now) ? Color.teal.opacity(0.15) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 2))
                                .clipped()
                        }.buttonStyle(.plain).focusEffectDisabled().focused(focusedProgramme, equals: item.id)
                            #if os(iOS)
                            .contextMenu { DownloadMenu(programme: item, station: station) }
                            #endif
                            .accessibilityLabel("\(station.title), \(item.show.title), \(BroadcastDate.time(item.show.start)) to \(BroadcastDate.time(item.show.end))")
                            .offset(x: stationWidth + CGFloat(start.timeIntervalSince(date) / 3600) * hourWidth)
                            .onChange(of: focusedProgramme.wrappedValue) { _, focus in if focus == item.id { select(item) } }
                    }
    }
}

private extension View {
    @ViewBuilder func guideHorizontalOffset(_ offset: Binding<CGFloat>) -> some View {
        if #available(iOS 18.0, tvOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.x + geometry.contentInsets.leading)
            } action: { _, value in offset.wrappedValue = value }
        } else { self }
    }
}

#if os(tvOS)
import UIKit

struct TVNativeGuide: UIViewControllerRepresentable {
    let playerStation: Station
    let stations: [Station]
    let date: Date
    let select: (ScheduledProgramme, Station) -> Void
    let activate: (ScheduledProgramme, Station) -> Void
    func makeUIViewController(context: Context) -> TVGuideController { TVGuideController() }
    func updateUIViewController(_ controller: TVGuideController, context: Context) {
        controller.selected = select
        controller.activated = activate
        controller.load(stations: stations, day: date, initialStation: playerStation)
    }
}

private struct TVGuideEntry {
    let station: Station?
    let programme: ScheduledProgramme?
    let text: String
    let frame: CGRect
    let pinnedColumn: Bool
    let pinnedHeader: Bool
}

final class TVGuideController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    var selected: ((ScheduledProgramme, Station) -> Void)?
    var activated: ((ScheduledProgramme, Station) -> Void)?
    private var key = ""
    private var entries: [TVGuideEntry] = []
    private var stations: [Station] = []
    private var rows: [String: [ScheduledProgramme]] = [:]
    private var failures = Set<String>()
    private var day = Date()
    private var loading: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var initialStation: Station = .defaultStation
    private var positioned = false
    private let column: CGFloat = 246
    private let rowHeight: CGFloat = 104
    private let header: CGFloat = 46
    private let hourWidth: CGFloat = 270
    private let layout = TVGuideLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var imageTasks: [URL: Task<Void, Never>] = [:]
    private let images = NSCache<NSURL, UIImage>()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        collection.backgroundColor = .black
        collection.dataSource = self; collection.delegate = self
        collection.register(TVGuideCell.self, forCellWithReuseIdentifier: "cell")
        collection.contentInsetAdjustmentBehavior = .never
        collection.remembersLastFocusedIndexPath = true
        collection.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collection)
        NSLayoutConstraint.activate([collection.leadingAnchor.constraint(equalTo:view.leadingAnchor), collection.trailingAnchor.constraint(equalTo:view.trailingAnchor), collection.topAnchor.constraint(equalTo:view.topAnchor), collection.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
    }
    func load(stations: [Station], day: Date, initialStation: Station) {
        let newKey = BroadcastDate.key(day) + stations.map(\.id).joined(separator: ",")
        guard key != newKey else { return }
        loadViewIfNeeded()
        key = newKey; self.stations = stations; self.day = day; self.initialStation = initialStation
        loading?.cancel(); previewTask?.cancel(); rows = [:]; failures = []; positioned = false
        rebuild()
        loading = Task { [weak self] in
            guard let self else { return }
            let ordered = [initialStation] + stations.filter { $0 != initialStation }
            // Bounded network work; layout/scrolling stays entirely on UICollectionView.
            for start in stride(from: 0, to: ordered.count, by: 6) {
                guard !Task.isCancelled else { return }
                let batch = Array(ordered[start..<min(start + 6, ordered.count)])
                let results = await withTaskGroup(of: (String, [ScheduledProgramme]?).self) { group in
                    for station in batch {
                        group.addTask { (station.id, try? await ScheduleCache.shared.load(station: station.id, day: day)) }
                    }
                    var output: [(String, [ScheduledProgramme]?)] = []
                    for await result in group { output.append(result) }
                    return output
                }
                guard !Task.isCancelled, self.key == newKey else { return }
                for (id, items) in results {
                    if let items { self.rows[id] = items } else { self.failures.insert(id) }
                }
                // Publish once so loading later stations cannot move remote focus.
                if start + 6 >= ordered.count { self.positioned = false; self.rebuild(); self.positioned = true }
                if !self.positioned, let initial = self.rows[initialStation.id] {
                    self.positioned = true
                    let current = initial.first(where: { $0.isLive(at:Date()) }) ?? initial.first
                    if let current { self.selected?(current, initialStation) }
                }
            }
        }
    }
    private func rebuild() {
        let end = BroadcastDate.adding(1,to:day)
        let hours = Int(end.timeIntervalSince(day)/3600)
        var next: [TVGuideEntry] = []
        next.append(TVGuideEntry(station:nil,programme:nil,text:"STATIONS",frame:CGRect(x:0,y:0,width:column,height:header),pinnedColumn:true,pinnedHeader:true))
        for hour in 0..<hours {
            next.append(TVGuideEntry(station:nil,programme:nil,text:BroadcastDate.time(day.addingTimeInterval(Double(hour)*3600)),frame:CGRect(x:column+CGFloat(hour)*hourWidth,y:0,width:hourWidth,height:header),pinnedColumn:false,pinnedHeader:true))
        }
        for (index,station) in stations.enumerated() {
            let y = header + CGFloat(index)*rowHeight
            next.append(TVGuideEntry(station:station,programme:nil,text:station.title,frame:CGRect(x:0,y:y,width:column,height:rowHeight),pinnedColumn:true,pinnedHeader:false))
            for item in rows[station.id] ?? [] {
                let start = max(day,item.show.start); let finish = min(end,item.show.end)
                guard finish > start else { continue }
                let x = column + CGFloat(start.timeIntervalSince(day)/3600)*hourWidth
                let width = CGFloat(finish.timeIntervalSince(start)/3600)*hourWidth
                next.append(TVGuideEntry(station:station,programme:item,text:item.show.title,frame:CGRect(x:x,y:y+3,width:max(2,width-4),height:rowHeight-6),pinnedColumn:false,pinnedHeader:false))
            }
            if rows[station.id]?.isEmpty != false {
                let status = failures.contains(station.id) ? "Schedule unavailable" : (rows[station.id] == nil ? "Loading…" : "No schedule published")
                next.append(TVGuideEntry(station:station,programme:nil,text:status,frame:CGRect(x:column,y:y,width:CGFloat(hours)*hourWidth,height:rowHeight),pinnedColumn:false,pinnedHeader:false))
            }
        }
        entries = next
        layout.frames = next.map(\.frame); layout.columnPinned = next.map(\.pinnedColumn); layout.headerPinned = next.map(\.pinnedHeader)
        layout.stationWidth = column
        layout.size = CGSize(width:column+CGFloat(hours)*hourWidth,height:header+CGFloat(stations.count)*rowHeight)
        collection.reloadData(); layout.invalidateLayout()
        if !positioned {
            collection.layoutIfNeeded()
            let hour = BroadcastDate.day(Date()) == day ? max(0, Date().timeIntervalSince(day)/3600 - 0.25) : 0
            let stationIndex = stations.firstIndex(of:initialStation) ?? 0
            collection.setContentOffset(CGPoint(x:min(CGFloat(hour)*hourWidth,max(0,layout.size.width-collection.bounds.width)),y:min(CGFloat(stationIndex)*rowHeight,max(0,layout.size.height-collection.bounds.height))),animated:false)
        }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier:"cell",for:indexPath) as! TVGuideCell
        let entry = entries[indexPath.item]
        cell.configure(entry, now:Date())
        cell.leadingOcclusion = entry.pinnedColumn ? 0 : max(0, min(entry.frame.width - 4, collection.contentOffset.x + column - entry.frame.minX))
        if entry.pinnedColumn, !entry.pinnedHeader, let station = entry.station,
           let url = rows[station.id]?.first(where: { $0.isLive(at:Date()) })?.show.imageURL {
            cell.icon.image = images.object(forKey:url as NSURL)
            if cell.icon.image == nil, imageTasks[url] == nil {
                imageTasks[url] = Task { [weak self] in
                    guard let (data,response) = try? await URLSession.shared.data(from:url), (response as? HTTPURLResponse)?.statusCode == 200,
                          let image = UIImage(data:data)?.preparingThumbnail(of:CGSize(width:96,height:96)) else { return }
                    self?.images.setObject(image,forKey:url as NSURL)
                    guard let self else { return }
                    for visible in self.collection.indexPathsForVisibleItems where self.entries[visible.item].station?.id == station.id && self.entries[visible.item].pinnedColumn {
                        (self.collection.cellForItem(at:visible) as? TVGuideCell)?.icon.image = image
                    }
                }
            }
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool { entries[indexPath.item].programme != nil }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard entries.indices.contains(indexPath.item), let programme = entries[indexPath.item].programme, let station = entries[indexPath.item].station else { return }
        previewTask?.cancel()
        activated?(programme, station)
    }
    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        if let next = context.nextFocusedIndexPath { choose(next) }
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        for index in collection.indexPathsForVisibleItems {
            guard entries.indices.contains(index.item), let cell = collection.cellForItem(at:index) as? TVGuideCell else { continue }
            let entry = entries[index.item]
            cell.leadingOcclusion = entry.pinnedColumn ? 0 : max(0, min(entry.frame.width - 4, collection.contentOffset.x + column - entry.frame.minX))
        }
    }
    private func choose(_ index: IndexPath) {
        guard entries.indices.contains(index.item), let programme = entries[index.item].programme, let station = entries[index.item].station else { return }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(140)) } catch { return }
            self?.selected?(programme,station)
        }
    }
    deinit { loading?.cancel(); previewTask?.cancel(); imageTasks.values.forEach { $0.cancel() } }
}

private final class TVGuideLayout: UICollectionViewLayout {
    var frames: [CGRect] = []
    var columnPinned: [Bool] = []
    var headerPinned: [Bool] = []
    var stationWidth: CGFloat = 246
    var size: CGSize = .zero
    override var collectionViewContentSize: CGSize { size }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard frames.indices.contains(indexPath.item), let collectionView else { return nil }
        let a = UICollectionViewLayoutAttributes(forCellWith:indexPath)
        var frame = frames[indexPath.item]
        if columnPinned[indexPath.item] { frame.origin.x = max(0,collectionView.contentOffset.x); a.zIndex = 10 }
        if headerPinned[indexPath.item] { frame.origin.y = max(0,collectionView.contentOffset.y); a.zIndex += 20 }
        a.frame = frame
        return a
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        frames.indices.compactMap { index in
            let base = frames[index]
            // Skip offscreen rows before allocating layout attributes.
            guard headerPinned[index] || base.maxY >= rect.minY && base.minY <= rect.maxY else { return nil }
            let attribute = layoutAttributesForItem(at:IndexPath(item:index,section:0))!
            return attribute.frame.intersects(rect) ? attribute : nil
        }
    }
}

private final class TVGuideCell: UICollectionViewCell {
    let icon = UIImageView()
    private let title = UILabel()
    private let time = UILabel()
    private var isProgramme = false
    private var live = false
    var leadingOcclusion: CGFloat = 0 { didSet { if oldValue != leadingOcclusion { setNeedsLayout() } } }
    override init(frame:CGRect) {
        super.init(frame:frame)
        contentView.clipsToBounds = true
        contentView.addSubview(title); contentView.addSubview(time); contentView.addSubview(icon)
        title.font = .systemFont(ofSize:24,weight:.semibold); title.numberOfLines = 2; title.textColor = .white
        time.font = .systemFont(ofSize:18,weight:.bold); time.textColor = .systemTeal
        icon.contentMode = .scaleAspectFill; icon.clipsToBounds = true; icon.layer.cornerRadius = 24
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ entry:TVGuideEntry, now:Date) {
        icon.image = nil; icon.isHidden = !entry.pinnedColumn || entry.pinnedHeader
        isProgramme = entry.programme != nil; live = entry.programme?.isLive(at:now) == true
        title.text = entry.text
        time.text = entry.programme.map { BroadcastDate.time($0.show.start) + (live ? " · LIVE" : "") }
        title.font = .systemFont(ofSize:entry.pinnedColumn ? 22 : 24,weight:.semibold)
        contentView.layer.cornerRadius = isProgramme ? 10 : 0
        accessibilityLabel = [entry.station?.title,entry.programme?.show.title,time.text].compactMap{$0}.joined(separator:", ")
        style(); setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset:CGFloat = 12
        icon.frame = CGRect(x:inset,y:(bounds.height-48)/2,width:48,height:48)
        let left:CGFloat = icon.isHidden ? inset + leadingOcclusion : 70
        let top:CGFloat = isProgramme ? 36 : 8
        title.frame = CGRect(x:left,y:top,width:max(0,bounds.width-left-inset),height:max(0,bounds.height-top-8))
        time.frame = CGRect(x:left,y:10,width:max(0,bounds.width-left-inset),height:24)
    }
    override func didUpdateFocus(in context:UIFocusUpdateContext, with coordinator:UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in:context,with:coordinator); style()
    }
    private func style() {
        contentView.backgroundColor = isFocused ? UIColor.systemTeal.withAlphaComponent(0.28) : (live ? UIColor.systemTeal.withAlphaComponent(0.12) : UIColor(white:0.07,alpha:1))
        contentView.layer.borderWidth = isProgramme ? (isFocused ? 3 : 1) : 0
        contentView.layer.borderColor = (isFocused ? UIColor.white : UIColor(white:0.22,alpha:1)).cgColor
    }
}
#endif


extension ScheduledProgramme {
    func matchesScheduleSearch(_ query: String, station: Station) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let text = [station.title, show.title, show.subtitle ?? "", show.synopsis ?? ""].joined(separator: " ")
        return terms.allSatisfy { text.localizedStandardContains($0) }
    }
}

struct ScheduleSearchControl: ViewModifier {
    @Binding var query: String
    @State private var expanded = false
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                if expanded {
                    Image(systemName: "magnifyingglass").foregroundStyle(.teal)
                    TextField("Search schedules", text: $query).focused($focused)
                        .accessibilityLabel("Search schedules")
                    Button { query = ""; expanded = false; focused = false } label: {
                        Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Close search and show all programmes")
                } else {
                    Spacer()
                    Button { expanded = true; focused = true } label: {
                        Image(systemName: "magnifyingglass").font(.title2).frame(width: 48, height: 48)
                            .background(.teal.opacity(0.15), in: Circle())
                    }.accessibilityLabel("Search schedules")
                }
            }.padding(.horizontal, 16).padding(.vertical, 6).background(.regularMaterial)
        }
    }
}
