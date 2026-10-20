import Foundation
#if os(iOS)
import Intents
#endif

struct Station: Identifiable, Equatable {
    let id: String
    let title: String
    let group: String
    let aliases: [String]
    var shortTitle: String { title }
    static func ordered(favourites: Set<String>) -> [Station] {
        all.filter { favourites.contains($0.id) } + all.filter { !favourites.contains($0.id) }
    }
    static let groups = ["National", "Nations", "Local radio"]
    static let all: [Station] = [
        Station(id: "bbc_radio_one", title: "BBC Radio 1", group: "National", aliases: ["Radio 1", "1"]),
        Station(id: "bbc_radio_one_anthems", title: "BBC Radio 1 Anthems", group: "National", aliases: ["Radio 1 Anthems", "1 Anthems"]),
        Station(id: "bbc_radio_one_dance", title: "BBC Radio 1 Dance", group: "National", aliases: ["Radio 1 Dance", "1 Dance"]),
        Station(id: "bbc_1xtra", title: "BBC Radio 1Xtra", group: "National", aliases: ["Radio 1Xtra", "1Xtra", "1 Extra", "Radio 1 Extra"]),
        Station(id: "bbc_radio_two", title: "BBC Radio 2", group: "National", aliases: ["Radio 2", "2"]),
        Station(id: "bbc_radio_three", title: "BBC Radio 3", group: "National", aliases: ["Radio 3", "3"]),
        Station(id: "bbc_radio_three_unwind", title: "BBC Radio 3 Unwind", group: "National", aliases: ["Radio 3 Unwind", "3 Unwind"]),
        Station(id: "bbc_radio_four_extra", title: "BBC Radio 4 Extra", group: "National", aliases: ["Radio 4 Extra", "4 Extra"]),
        Station(id: "bbc_radio_five_live", title: "BBC Radio 5 Live", group: "National", aliases: ["Radio 5 Live", "5 Live"]),
        Station(id: "bbc_radio_five_live_sports_extra", title: "BBC Radio 5 Sports Extra", group: "National", aliases: ["Radio 5 Sports Extra", "5 Sports Extra", "5 Live Sports Extra", "Radio 5 Live Sports Extra"]),
        Station(id: "bbc_radio_five_sports_extra_2", title: "BBC Radio 5 Sports Extra 2", group: "National", aliases: ["Radio 5 Sports Extra 2", "5 Sports Extra 2"]),
        Station(id: "bbc_radio_five_sports_extra_3", title: "BBC Radio 5 Sports Extra 3", group: "National", aliases: ["Radio 5 Sports Extra 3", "5 Sports Extra 3"]),
        Station(id: "bbc_6music", title: "BBC Radio 6 Music", group: "National", aliases: ["Radio 6 Music", "6 Music", "6 Music"]),
        Station(id: "bbc_radio_six_indie_forever", title: "BBC Radio 6 Indie Forever", group: "National", aliases: ["Radio 6 Indie Forever", "6 Indie Forever"]),
        Station(id: "bbc_asian_network", title: "BBC Asian Network", group: "National", aliases: ["Asian Network"]),
        Station(id: "bbc_world_service", title: "BBC World Service", group: "National", aliases: ["World Service"]),
        Station(id: "bbc_sounds_news", title: "BBC Live News", group: "National", aliases: ["Live News"]),
        Station(id: "bbc_radio_scotland_mw", title: "BBC Radio Scotland Extra", group: "Nations", aliases: ["Radio Scotland Extra", "Scotland Extra"]),
        Station(id: "bbc_radio_orkney", title: "BBC Radio Orkney", group: "Nations", aliases: ["Radio Orkney", "Orkney"]),
        Station(id: "bbc_radio_shetland", title: "BBC Radio Shetland", group: "Nations", aliases: ["Radio Shetland", "Shetland"]),
        Station(id: "bbc_radio_nan_gaidheal", title: "BBC Radio nan Gàidheal", group: "Nations", aliases: ["Radio nan Gàidheal", "nan Gàidheal"]),
        Station(id: "bbc_radio_ulster", title: "BBC Radio Ulster", group: "Nations", aliases: ["Radio Ulster", "Ulster"]),
        Station(id: "bbc_radio_foyle", title: "BBC Radio Foyle", group: "Nations", aliases: ["Radio Foyle", "Foyle"]),
        Station(id: "bbc_radio_wales_am", title: "BBC Radio Wales Extra", group: "Nations", aliases: ["Radio Wales Extra", "Wales Extra"]),
        Station(id: "bbc_radio_cymru", title: "BBC Radio Cymru", group: "Nations", aliases: ["Radio Cymru", "Cymru"]),
        Station(id: "bbc_radio_cymru_2", title: "BBC Radio Cymru 2", group: "Nations", aliases: ["Radio Cymru 2", "Cymru 2"]),
        Station(id: "cbeebies_radio", title: "BBC CBeebies Radio", group: "National", aliases: ["CBeebies Radio"]),
        Station(id: "bbc_radio_berkshire", title: "BBC Radio Berkshire", group: "Local radio", aliases: ["Radio Berkshire", "Berkshire"]),
        Station(id: "bbc_radio_bristol", title: "BBC Radio Bristol", group: "Local radio", aliases: ["Radio Bristol", "Bristol"]),
        Station(id: "bbc_radio_cambridge", title: "BBC Radio Cambridgeshire", group: "Local radio", aliases: ["Radio Cambridgeshire", "Cambridgeshire"]),
        Station(id: "bbc_radio_cornwall", title: "BBC Radio Cornwall", group: "Local radio", aliases: ["Radio Cornwall", "Cornwall"]),
        Station(id: "bbc_radio_coventry_warwickshire", title: "BBC CWR", group: "Local radio", aliases: ["CWR", "Coventry and Warwickshire", "Radio Coventry and Warwickshire", "Coventry Warwickshire"]),
        Station(id: "bbc_radio_cumbria", title: "BBC Radio Cumbria", group: "Local radio", aliases: ["Radio Cumbria", "Cumbria"]),
        Station(id: "bbc_radio_derby", title: "BBC Radio Derby", group: "Local radio", aliases: ["Radio Derby", "Derby"]),
        Station(id: "bbc_radio_devon", title: "BBC Radio Devon", group: "Local radio", aliases: ["Radio Devon", "Devon"]),
        Station(id: "bbc_radio_essex", title: "BBC Essex", group: "Local radio", aliases: ["Essex", "Radio Essex"]),
        Station(id: "bbc_radio_gloucestershire", title: "BBC Radio Gloucestershire", group: "Local radio", aliases: ["Radio Gloucestershire", "Gloucestershire"]),
        Station(id: "bbc_radio_guernsey", title: "BBC Radio Guernsey", group: "Local radio", aliases: ["Radio Guernsey", "Guernsey"]),
        Station(id: "bbc_radio_hereford_worcester", title: "BBC Hereford & Worcester", group: "Local radio", aliases: ["Hereford & Worcester", "Radio Hereford and Worcester"]),
        Station(id: "bbc_radio_humberside", title: "BBC Radio Humberside", group: "Local radio", aliases: ["Radio Humberside", "Humberside"]),
        Station(id: "bbc_radio_jersey", title: "BBC Radio Jersey", group: "Local radio", aliases: ["Radio Jersey", "Jersey"]),
        Station(id: "bbc_radio_kent", title: "BBC Radio Kent", group: "Local radio", aliases: ["Radio Kent", "Kent"]),
        Station(id: "bbc_radio_lancashire", title: "BBC Radio Lancashire", group: "Local radio", aliases: ["Radio Lancashire", "Lancashire"]),
        Station(id: "bbc_radio_leeds", title: "BBC Radio Leeds", group: "Local radio", aliases: ["Radio Leeds", "Leeds"]),
        Station(id: "bbc_radio_leicester", title: "BBC Radio Leicester", group: "Local radio", aliases: ["Radio Leicester", "Leicester"]),
        Station(id: "bbc_radio_lincolnshire", title: "BBC Radio Lincolnshire", group: "Local radio", aliases: ["Radio Lincolnshire", "Lincolnshire"]),
        Station(id: "bbc_london", title: "BBC Radio London", group: "Local radio", aliases: ["Radio London", "London"]),
        Station(id: "bbc_radio_manchester", title: "BBC Radio Manchester", group: "Local radio", aliases: ["Radio Manchester", "Manchester"]),
        Station(id: "bbc_radio_merseyside", title: "BBC Radio Merseyside", group: "Local radio", aliases: ["Radio Merseyside", "Merseyside"]),
        Station(id: "bbc_radio_newcastle", title: "BBC Radio Newcastle", group: "Local radio", aliases: ["Radio Newcastle", "Newcastle"]),
        Station(id: "bbc_radio_norfolk", title: "BBC Radio Norfolk", group: "Local radio", aliases: ["Radio Norfolk", "Norfolk"]),
        Station(id: "bbc_radio_northampton", title: "BBC Radio Northampton", group: "Local radio", aliases: ["Radio Northampton", "Northampton"]),
        Station(id: "bbc_radio_nottingham", title: "BBC Radio Nottingham", group: "Local radio", aliases: ["Radio Nottingham", "Nottingham"]),
        Station(id: "bbc_radio_oxford", title: "BBC Radio Oxford", group: "Local radio", aliases: ["Radio Oxford", "Oxford"]),
        Station(id: "bbc_radio_sheffield", title: "BBC Radio Sheffield", group: "Local radio", aliases: ["Radio Sheffield", "Sheffield"]),
        Station(id: "bbc_radio_shropshire", title: "BBC Radio Shropshire", group: "Local radio", aliases: ["Radio Shropshire", "Shropshire"]),
        Station(id: "bbc_radio_solent", title: "BBC Radio Solent", group: "Local radio", aliases: ["Radio Solent", "Solent"]),
        Station(id: "bbc_radio_solent_west_dorset", title: "BBC Radio Solent Dorset", group: "Local radio", aliases: ["Radio Solent Dorset", "Solent Dorset"]),
        Station(id: "bbc_radio_somerset_sound", title: "BBC Radio Somerset", group: "Local radio", aliases: ["Radio Somerset", "Somerset"]),
        Station(id: "bbc_radio_stoke", title: "BBC Radio Stoke", group: "Local radio", aliases: ["Radio Stoke", "Stoke"]),
        Station(id: "bbc_radio_suffolk", title: "BBC Radio Suffolk", group: "Local radio", aliases: ["Radio Suffolk", "Suffolk"]),
        Station(id: "bbc_radio_surrey", title: "BBC Radio Surrey", group: "Local radio", aliases: ["Radio Surrey", "Surrey"]),
        Station(id: "bbc_radio_sussex", title: "BBC Radio Sussex", group: "Local radio", aliases: ["Radio Sussex", "Sussex"]),
        Station(id: "bbc_tees", title: "BBC Radio Tees", group: "Local radio", aliases: ["Radio Tees", "Tees"]),
        Station(id: "bbc_three_counties_radio", title: "BBC Three Counties Radio", group: "Local radio", aliases: ["Three Counties Radio", "Three Counties", "Radio Three Counties"]),
        Station(id: "bbc_radio_wiltshire", title: "BBC Radio Wiltshire", group: "Local radio", aliases: ["Radio Wiltshire", "Wiltshire"]),
        Station(id: "bbc_wm", title: "BBC Radio WM", group: "Local radio", aliases: ["Radio WM", "WM"]),
        Station(id: "bbc_radio_york", title: "BBC Radio York", group: "Local radio", aliases: ["Radio York", "York"]),
        Station(id: "bbc_radio_fourfm", title: "BBC Radio 4", group: "National", aliases: ["Radio 4", "4"]),
        Station(id: "bbc_radio_scotland_fm", title: "BBC Radio Scotland", group: "Nations", aliases: ["Radio Scotland", "Scotland"]),
        Station(id: "bbc_radio_wales_fm", title: "BBC Radio Wales", group: "Nations", aliases: ["Radio Wales", "Wales"]),
    ]
    static var defaultStation: Station { all.first { $0.id == "bbc_6music" }! }
    static func normalize(_ name: String) -> String {
        var words = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_GB"))
        words = words.replacingOccurrences(of: "&", with: " and ")
        for (word, number) in [("one", "1"), ("two", "2"), ("three", "3"), ("four", "4"), ("five", "5"), ("six", "6")] {
            words = words.replacingOccurrences(of: "\\b" + word + "\\b", with: number, options: .regularExpression)
        }
        let key = words.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return key.hasPrefix("bbc") ? String(key.dropFirst(3)) : key
    }
    static func named(_ name: String) -> Station? {
        let key = normalize(name)
        let matches = all.filter { normalize($0.title) == key || $0.aliases.contains { normalize($0) == key } }
        return matches.count == 1 ? matches[0] : nil
    }
#if os(iOS)
    var item: INMediaItem { INMediaItem(identifier: id, title: title, type: .radioStation, artwork: nil) }
    static func resolve(_ intent: INPlayMediaIntent) -> Station? {
        if let search = intent.mediaSearch {
            guard search.mediaType == .unknown || search.mediaType == .radioStation,
                  search.artistName == nil, search.albumName == nil else { return nil }
        }
        guard intent.mediaContainer == nil else { return nil }
        if let items = intent.mediaItems, !items.isEmpty {
            guard items.count == 1 else { return nil }
            if let id = items[0].identifier, let station = all.first(where: { $0.id == id }) { return station }
            return named(items[0].title ?? "")
        }
        if let name = intent.mediaSearch?.mediaName, !name.isEmpty { return named(name) }
        return defaultStation
    }
#endif
}
