import Foundation
import SQLite3

final class VRadioDatabase {
    static let shared = VRadioDatabase()
    private var db: OpaquePointer?

    private let baseSelect = """
        SELECT S.Id, S.Name, SI.StreamUrl, SI.Bitrate, SI.Format, S.Website,
               COALESCE(L.Name, '') AS LocName,
               COALESCE(C.Name, '') AS CountryName,
               COALESCE(G.Name, '') AS GenreName,
               COALESCE(SI.UserAgent, '') AS UA,
               COALESCE(SI.Referer, '') AS Ref
        FROM Station S
        JOIN StreamInfo SI ON S.Id = SI.StationId
             AND SI.rowid = (
                 SELECT SI2.rowid FROM StreamInfo SI2
                 WHERE SI2.StationId = S.Id AND SI2.StreamUrl != ''
                 ORDER BY
                     CASE WHEN SI2.StreamUrl LIKE '%streamtheworld%'
                               OR SI2.StreamUrl LIKE '%zeno%'
                               OR SI2.StreamUrl LIKE '%mdstrm%'
                               OR SI2.StreamUrl LIKE '%live-audio-aw%'
                               OR SI2.StreamUrl LIKE '%securenetsystems%'
                          THEN 1 ELSE 0 END,
                     SI2.No
                 LIMIT 1
             )
        LEFT JOIN LocationInfo LI ON S.Id = LI.StationId
        LEFT JOIN Location L ON LI.Location = L.Id
        LEFT JOIN Country C ON L.Country = C.Id
        LEFT JOIN Genre G ON S.Genre1 = G.Id
    """

    private init() {
        openDatabase()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        guard let url = Bundle.main.url(forResource: "vradio", withExtension: "db") else {
            print("[VRadioDatabase] vradio.db not found in bundle")
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("[VRadioDatabase] Error opening vradio.db")
            db = nil
        }
    }

    static func normalizeStreamUrl(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)

        if u.localizedCaseInsensitiveContains("servistream.info") {
            u = u.replacingOccurrences(of: "servistream.info:8340/stream", with: "servistreampro.info:8340/;")
                .replacingOccurrences(of: "servistream.info:8340/;", with: "servistreampro.info:8340/;")
                .replacingOccurrences(of: "servistream.info", with: "servistreampro.info")
        }
        if u.localizedCaseInsensitiveContains("live.discoteca90.com") {
            u = u.replacingOccurrences(of: "live.discoteca90.com:8004/discoteca90", with: "listen.discoteca90.com:8004/stream")
                .replacingOccurrences(of: "live.discoteca90.com", with: "listen.discoteca90.com")
        }

        // Mediastream: normalizar a endpoint HLS live.m3u8 para que HLSAdStripperResourceLoader purgue las cuñas AdsWizz
        if u.localizedCaseInsensitiveContains("mdstrm.com") {
            if let regex = try? NSRegularExpression(pattern: "([a-f0-9]{24})"),
               let match = regex.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
               let range = Range(match.range(at: 1), in: u) {
                let streamId = String(u[range])
                return "https://mdstrm.com/audio/\(streamId)/live.m3u8"
            }
        }
        return u
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }

    private func parseStation(_ stmt: OpaquePointer?) -> Station {
        let id = Int(sqlite3_column_int(stmt, 0))
        let name = columnString(stmt, 1)
        let rawUrl = columnString(stmt, 2)
        let streamUrl = Self.normalizeStreamUrl(rawUrl)
        let bitrate = Int(sqlite3_column_int(stmt, 3))
        let format = Int(sqlite3_column_int(stmt, 4))
        let website = columnString(stmt, 5)
        let loc = columnString(stmt, 6)
        let country = columnString(stmt, 7)
        let genre = columnString(stmt, 8)
        let ua = columnString(stmt, 9)
        let ref = columnString(stmt, 10)
        let codec = format == 2 ? "AAC" : "MP3"
        let favicon = "https://vradio.app/StatImage/\(id).png"

        return Station(
            id: id,
            name: name.isEmpty ? "Radio" : name,
            url: streamUrl,
            favicon: favicon,
            country: country,
            location: loc,
            genre: genre,
            bitrate: bitrate,
            codec: codec,
            website: website,
            streamUserAgent: ua,
            streamReferer: ref
        )
    }

    private func queryStations(sql: String, params: [String] = []) -> [Station] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        var list: [Station] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (idx, param) in params.enumerated() {
                sqlite3_bind_text(stmt, Int32(idx + 1), (param as NSString).utf8String, -1, nil)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let st = parseStation(stmt)
                if !st.url.isEmpty { list.append(st) }
            }
        }
        sqlite3_finalize(stmt)
        return list
    }

    func getPopularStations(limit: Int = 60) -> [Station] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        var ids: [String] = []
        if sqlite3_prepare_v2(db, "SELECT Ids FROM Rank WHERE Type = 1 LIMIT 1", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let raw = columnString(stmt, 0)
                ids = raw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }.prefix(limit).map { $0 }
            }
        }
        sqlite3_finalize(stmt)
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "\(baseSelect) WHERE S.Id IN (\(placeholders)) GROUP BY S.Id LIMIT \(limit)"
        return queryStations(sql: sql, params: ids)
    }

    func getPopularStationsByCountryIso(_ iso2: String, limit: Int = 60) -> [Station] {
        let clean = iso2.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return getPopularStations(limit: limit) }
        let sql = "\(baseSelect) WHERE UPPER(C.Iso2) = ? GROUP BY S.Id LIMIT \(limit)"
        let res = queryStations(sql: sql, params: [clean])
        return res.isEmpty ? getPopularStations(limit: limit) : res
    }

    func getSuggestedStations(limit: Int = 12) -> [Station] {
        let ids = [30684, 30676, 12839, 12838, 22836, 18792, 23473, 28779, 32850, 34159, 25226, 32041]
        return getStationsByIds(Array(ids.prefix(limit)))
    }

    func getStationsByIds(_ ids: [Int]) -> [Station] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "\(baseSelect) WHERE S.Id IN (\(placeholders)) GROUP BY S.Id"
        let fetched = queryStations(sql: sql, params: ids.map { String($0) })
        let byId = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    func searchStations(query: String, limit: Int = 60) -> [Station] {
        let q = "%\(query.trimmingCharacters(in: .whitespacesAndNewlines))%"
        let sql = """
            \(baseSelect)
            WHERE S.Name LIKE ? OR C.Name LIKE ? OR G.Name LIKE ?
            GROUP BY S.Id
            LIMIT \(limit)
        """
        return queryStations(sql: sql, params: [q, q, q])
    }

    func getCountries() -> [CountryItem] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        var list: [CountryItem] = []
        let sql = "SELECT Id, Name, StationsCount, COALESCE(Iso2, '') FROM Country WHERE StationsCount > 0 ORDER BY Name ASC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                list.append(CountryItem(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    name: columnString(stmt, 1),
                    stationsCount: Int(sqlite3_column_int(stmt, 2)),
                    iso2: columnString(stmt, 3)
                ))
            }
        }
        sqlite3_finalize(stmt)
        return list
    }

    func getStationsByCountry(countryId: Int, limit: Int = 200) -> [Station] {
        let sql = "\(baseSelect) WHERE C.Id = ? GROUP BY S.Id LIMIT \(limit)"
        return queryStations(sql: sql, params: [String(countryId)])
    }

    func getCategories() -> [CategoryItem] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        var list: [CategoryItem] = []
        let sql = "SELECT Id, Name, StationsCount FROM Category WHERE StationsCount > 0 ORDER BY StationsCount DESC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                list.append(CategoryItem(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    name: columnString(stmt, 1),
                    stationsCount: Int(sqlite3_column_int(stmt, 2))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return list
    }

    func getStationsByCategory(categoryId: Int, limit: Int = 100) -> [Station] {
        let sql = "\(baseSelect) WHERE S.Genre1 = ? GROUP BY S.Id LIMIT \(limit)"
        return queryStations(sql: sql, params: [String(categoryId)])
    }

    func getNetworks() -> [NetworkItem] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        var list: [NetworkItem] = []
        let sql = "SELECT Id, Name, StationsCount FROM Network WHERE StationsCount > 1 ORDER BY StationsCount DESC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                list.append(NetworkItem(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    name: columnString(stmt, 1),
                    stationsCount: Int(sqlite3_column_int(stmt, 2))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return list
    }

    func getStationsByNetwork(networkId: Int, limit: Int = 100) -> [Station] {
        let sql = "\(baseSelect) WHERE S.Network = ? GROUP BY S.Id LIMIT \(limit)"
        return queryStations(sql: sql, params: [String(networkId)])
    }
}
