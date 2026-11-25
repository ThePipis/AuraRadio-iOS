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

    private init() {
        loadAll()
    }

    private func loadAll() {
        favorites = decode([Station].self, key: "fav_list") ?? []
        recentIds = defaults.array(forKey: "recent_ids") as? [Int] ?? [30676, 12839, 30684, 22836]
        recentCountries = defaults.stringArray(forKey: "recent_countries") ?? []
        blacklistedStations = decode([Station].self, key: "blacklist_json") ?? []
        detectedCountryIso = defaults.string(forKey: "detected_country_iso") ?? ""
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
}
