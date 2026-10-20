import CarPlay
import Combine

@MainActor final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interface: CPInterfaceController?
    private var scheduleTask: Task<Void, Never>?
    private let schedules = CPListTemplate(title: "Schedules", sections: [])
    private var subscription: AnyCancellable?
    private let favourites = CPListTemplate(title: "Favourites", sections: [])
    private let stations = CPListTemplate(title: "BBC stations", sections: [])
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        favourites.tabImage = UIImage(systemName: "star.fill")
        stations.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")
        schedules.tabImage = UIImage(systemName: "calendar")
        refresh()
        interfaceController.setRootTemplate(CPTabBarTemplate(templates: [favourites, stations, schedules]), animated: false, completion: nil)
        subscription = RadioPlayer.shared.$favouriteIDs.combineLatest(RadioPlayer.shared.$station)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
    }
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        scheduleTask?.cancel()
        subscription = nil
        interface = nil
    }
    private func refresh() {
        let player = RadioPlayer.shared
        let favs = Station.ordered(favourites: player.favouriteIDs).filter { player.favouriteIDs.contains($0.id) }
        if favs.isEmpty {
            let hint = CPListItem(text: "No favourites yet", detailText: "Add favourites in Sounds Like on your iPhone or iPad.")
            hint.isEnabled = false
            favourites.updateSections([CPListSection(items: [hint])])
        } else { favourites.updateSections([CPListSection(items: favs.map(item))]) }
        stations.updateSections([CPListSection(items: Station.all.map(item))])
        let days = (-1...1).map { offset -> CPListItem in
            let date = BroadcastDate.adding(offset, to: BroadcastDate.day(Date()))
            let row = CPListItem(text: BroadcastDate.label(date), detailText: player.station.title)
            row.handler = { [weak self] _, completion in
                self?.openSchedule(station: player.station, date: date); completion()
            }
            return row
        }
        schedules.updateSections([CPListSection(items: days)])
        let button = CPNowPlayingImageButton(image: UIImage(systemName: player.favouriteIDs.contains(player.station.id) ? "star.fill" : "star")!) { _ in
            RadioPlayer.shared.toggleFavourite(RadioPlayer.shared.station)
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([button])
    }
    private func openSchedule(station: Station, date: Date) {
        scheduleTask?.cancel()
        let placeholder = CPListItem(text: "Loading schedule…", detailText: nil); placeholder.isEnabled = false
        let template = CPListTemplate(title: "\(station.title) · \(BroadcastDate.label(date))", sections: [CPListSection(items: [placeholder])])
        interface?.pushTemplate(template, animated: true, completion: nil)
        scheduleTask = Task { [weak self] in
            do {
                let programmes = try await ScheduleCache.shared.load(station: station.id, day: date)
                try Task.checkCancellation()
                let rows = programmes.prefix(100).map { programme -> CPListItem in
                    let live = programme.isLive(at: Date())
                    let past = programme.show.end <= Date()
                    let available = past && programme.availability == "available" && !programme.unavailable(at: Date())
                    let detail = live ? "Live · Play station" : (available ? "Catch-up · Check and play" : (past ? "Unavailable in CarPlay" : "Upcoming"))
                    let row = CPListItem(text: "\(BroadcastDate.time(programme.show.start)) · \(programme.show.title)", detailText: detail)
                    row.isEnabled = live || available
                    row.handler = { [weak self] _, completion in
                        Task { @MainActor in
                            defer { completion() }
                            if programme.isLive(at: Date()) { RadioPlayer.shared.play(station: station) }
                            else {
                                guard (try? await CatchupResolver.shared.resolve(programme)) != nil else {
                                    row.setDetailText("Playback unavailable"); row.isEnabled = false; return
                                }
                                RadioPlayer.shared.playEpisode(programme, station: station)
                            }
                            self?.interface?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                        }
                    }
                    return row
                }
                if rows.isEmpty { placeholder.setText("No schedule published"); template.updateSections([CPListSection(items: [placeholder])]) }
                else { template.updateSections([CPListSection(items: rows)]) }
            } catch {
                if !Task.isCancelled {
                    placeholder.setText("Schedule unavailable"); placeholder.setDetailText("Select to retry"); placeholder.isEnabled = true
                    placeholder.handler = { [weak self] _, completion in self?.interface?.popTemplate(animated: false, completion: nil); self?.openSchedule(station: station, date: date); completion() }
                }
            }
        }
    }
    private func item(_ station: Station) -> CPListItem {
        let row = CPListItem(text: station.title, detailText: RadioPlayer.shared.station == station ? "Selected station" : nil)
        row.handler = { [weak self] _, completion in
            RadioPlayer.shared.play(station: station)
            self?.interface?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            completion()
        }
        return row
    }
}
