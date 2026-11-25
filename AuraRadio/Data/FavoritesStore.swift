import Foundation
import Combine

final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()
    private let defaults = UserDefaults.standard

    @Published private(set) var favorites: [Station] = []
    @Published private(set) var recentIds: [Int] = []
    @Published private(set) var recentCountries: [String] = []
    @Published private(set) var blacklistedStations: [Station] = []
    @Published private(set) var detectedCountryIso: String = ""
    @Published private(set) var songHistory: [SongHistoryItem] = []
    @Published private(set) var songCollection: [SongHistoryItem] = []
    @Published private(set) var userStations: [Station] = []
    @Published private(set) var wifiBytes: Int64 = 0
    @Published private(set) var mobileBytes: Int64 = 0

    private init() {
        loadAll()
    }

    private func loadAll() {
        favorites = decode([Station].self, key: "fav_list") ?? []
        recentIds = defaults.array(forKey: "recent_ids") as? [Int] ?? [30676, 12839, 30684, 22836]
        recentCountries = defaults.stringArray(forKey: "recent_countries") ?? []
        blacklistedStations = decode([Station].self, key: "blacklist_json") ?? []
        detectedCountryIso = defaults.string(forKey: "detected_country_iso") ?? ""
        songHistory = decode([SongHistoryItem].self, key: "song_history") ?? []
        songCollection = decode([SongHistoryItem].self, key: "song_collection") ?? []
        userStations = decode([Station].self, key: "user_stations") ?? []
        wifiBytes = Int64(defaults.double(forKey: "wifi_bytes"))
        mobileBytes = Int64(defaults.double(forKey: "mobile_bytes"))
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - Favoritas
    func isFavorite(_ id: Int) -> Bool {
        favorites.contains { $0.id == id }
    }

    @discardableResult
    func toggleFavorite(_ station: Station) -> Bool {
        var current = favorites
        let nowFav: Bool
        if let idx = current.firstIndex(where: { $0.id == station.id }) {
            current.remove(at: idx)
            nowFav = false
        } else {
            current.insert(station, at: 0)
            nowFav = true
        }
        favorites = current
        encode(current, key: "fav_list")
        return nowFav
    }

    // MARK: - Recientes
    func addRecentStation(_ id: Int) {
        guard id > 0 else { return }
        var current = recentIds.filter { $0 != id }
        current.insert(id, at: 0)
        recentIds = Array(current.prefix(25))
        defaults.set(recentIds, forKey: "recent_ids")
    }

    func clearRecents() {
        recentIds = []
        defaults.set([], forKey: "recent_ids")
    }

    // MARK: - Última emisora (Auto-Play)
    func saveLastPlayedStation(_ station: Station) {
        encode(station, key: "last_played_station")
        defaults.synchronize()
    }

    func getLastPlayedStation() -> Station? {
        decode(Station.self, key: "last_played_station")
    }

    // MARK: - Países Recientes (máx 10 LRU)
    func setLastPlayedCountry(_ country: String) {
        let clean = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var current = recentCountries.filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        current.insert(clean, at: 0)
        recentCountries = Array(current.prefix(10))
        defaults.set(recentCountries, forKey: "recent_countries")
    }

    // MARK: - GeoIP País
    func setDetectedCountryIso(_ iso: String) {
        let clean = iso.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        detectedCountryIso = clean
        defaults.set(clean, forKey: "detected_country_iso")
    }

    // MARK: - Lista Negra
    var blacklistedIds: Set<Int> {
        Set(blacklistedStations.map { $0.id })
    }

    func addToBlacklist(_ station: Station) {
        if !blacklistedStations.contains(where: { $0.id == station.id }) {
            var current = blacklistedStations
            current.insert(station, at: 0)
            blacklistedStations = current
            encode(current, key: "blacklist_json")
        }
        favorites = favorites.filter { $0.id != station.id }
        encode(favorites, key: "fav_list")
        recentIds = recentIds.filter { $0 != station.id }
        defaults.set(recentIds, forKey: "recent_ids")
    }

    func removeFromBlacklist(_ stationId: Int) {
        blacklistedStations = blacklistedStations.filter { $0.id != stationId }
        encode(blacklistedStations, key: "blacklist_json")
    }

    func exportBlacklistTxt() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines: [String] = [
            "=== AURARADIO iOS - LISTA NEGRA DE EMISORAS ===",
            "Fecha: \(formatter.string(from: Date()))",
            "Total bloqueadas: \(blacklistedStations.count)",
            ""
        ]
        let grouped = Dictionary(grouping: blacklistedStations) {
            $0.country.isEmpty ? "Sin País Especificado" : $0.country
        }
        for country in grouped.keys.sorted() {
            let list = grouped[country] ?? []
            lines.append("[\(country)] (\(list.count))")
            for st in list {
                lines.append("  - ID: \(st.id) | \(st.name) | \(st.streamFormatBadge) | URL: \(st.url)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Historial y Colección de Títulos
    func addSongHistory(title: String, artist: String, stationName: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        if let first = songHistory.first,
           first.title.caseInsensitiveCompare(cleanTitle) == .orderedSame,
           first.stationName.caseInsensitiveCompare(stationName) == .orderedSame {
            return
        }
        let item = SongHistoryItem(
            id: UUID().uuidString,
            title: cleanTitle,
            artist: artist.isEmpty ? stationName : artist,
            stationName: stationName,
            timestamp: Date().timeIntervalSince1970
        )
        var current = songHistory
        current.insert(item, at: 0)
        songHistory = Array(current.prefix(100))
        encode(songHistory, key: "song_history")
    }

    func clearSongHistory() {
        songHistory = []
        encode(songHistory, key: "song_history")
    }

    @discardableResult
    func toggleSongInCollection(_ item: SongHistoryItem) -> Bool {
        var current = songCollection
        if let idx = current.firstIndex(where: { $0.id == item.id || ($0.title == item.title && $0.stationName == item.stationName) }) {
            current.remove(at: idx)
            songCollection = current
            encode(current, key: "song_collection")
            return false
        } else {
            current.insert(item, at: 0)
            songCollection = current
            encode(current, key: "song_collection")
            return true
        }
    }

    func isSongSaved(_ item: SongHistoryItem) -> Bool {
        songCollection.contains { $0.id == item.id || ($0.title == item.title && $0.stationName == item.stationName) }
    }

    // MARK: - Emisoras de Usuario
    func addUserStation(name: String, url: String, genre: String = "Personalizada") {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanUrl.isEmpty else { return }
        let newId = -Int(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1_000_000)) - Int.random(in: 1...999)
        let st = Station(
            id: newId,
            name: cleanName,
            url: cleanUrl,
            favicon: "",
            country: "Usuario",
            location: "Personalizada",
            genre: genre,
            bitrate: 128,
            codec: "STREAM",
            website: "",
            streamUserAgent: "",
            streamReferer: ""
        )
        var current = userStations
        current.insert(st, at: 0)
        userStations = current
        encode(current, key: "user_stations")
    }

    func removeUserStation(_ id: Int) {
        userStations = userStations.filter { $0.id != id }
        encode(userStations, key: "user_stations")
    }

    // MARK: - Uso de Datos
    func addDataUsage(bytes: Int64, isWifi: Bool) {
        guard bytes > 0 else { return }
        if isWifi {
            wifiBytes += bytes
            defaults.set(Double(wifiBytes), forKey: "wifi_bytes")
        } else {
            mobileBytes += bytes
            defaults.set(Double(mobileBytes), forKey: "mobile_bytes")
        }
    }

    func resetDataUsage() {
        wifiBytes = 0
        mobileBytes = 0
        defaults.set(0.0, forKey: "wifi_bytes")
        defaults.set(0.0, forKey: "mobile_bytes")
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb < 1024.0 {
            return String(format: "%.1f MB", mb)
        }
        return String(format: "%.2f GB", mb / 1024.0)
    }
}
