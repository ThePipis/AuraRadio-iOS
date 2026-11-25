import Foundation

struct Station: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let name: String
    let url: String
    let favicon: String
    let country: String
    let location: String
    let genre: String
    let bitrate: Int
    let codec: String
    let website: String
    let streamUserAgent: String
    let streamReferer: String

    var subtitleInfo: String {
        let parts = [location, country].filter { !$0.isEmpty }
        let locStr = parts.joined(separator: ", ")
        if !locStr.isEmpty && !genre.isEmpty {
            return "\(locStr) • \(genre)"
        } else if !locStr.isEmpty {
            return locStr
        } else if !genre.isEmpty {
            return genre
        }
        return "Radio En Vivo"
    }

    var streamFormatBadge: String {
        let c = codec.isEmpty ? "AAC" : codec
        let b = bitrate > 0 ? "\(bitrate)K" : "HD"
        return "\(c) / \(b)"
    }
}

struct CountryItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let stationsCount: Int
    let iso2: String

    var flagURL: URL? {
        if !iso2.isEmpty {
            return URL(string: "https://flagcdn.com/w160/\(iso2.lowercased()).png")
        }
        return URL(string: "https://vradio.app/CFlag/\(id).png")
    }
}

struct CategoryItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let stationsCount: Int
}

struct NetworkItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let stationsCount: Int
}

struct SongHistoryItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let stationName: String
    let timestamp: TimeInterval
}

enum AppRoute: Hashable {
    case countries
    case categories
    case networks
    case popular
    case favorites
    case recent
    case blacklist
    case songHistory
    case songCollection
    case userStations
    case recordings
    case alarms
    case equalizer
    case settings
}
