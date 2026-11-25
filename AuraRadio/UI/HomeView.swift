import SwiftUI

struct HomeView: View {
    @ObservedObject var player = RadioPlayerService.shared
    @ObservedObject var store = FavoritesStore.shared

    @State private var searchQuery = ""
    @State private var showFullPlayer = false
    @State private var suggested: [Station] = []
    @State private var recents: [Station] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.darkBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Explorar
                        Text("Explorar")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            NavigationLink(destination: CountriesGridView()) {
                                ExploreTile(icon: "globe", title: "Países y Regiones", color: .neonCyan)
                            }
                            NavigationLink(destination: CategoriesListView()) {
                                ExploreTile(icon: "music.note.list", title: "Categorías", color: .green)
                            }
                            NavigationLink(destination: PopularStationsView()) {
                                ExploreTile(icon: "flame.fill", title: "Emisoras Populares", color: .orange)
                            }
                            NavigationLink(destination: FavoritesListView()) {
                                ExploreTile(icon: "heart.fill", title: "Mis Favoritas", color: .accentRed)
                            }
                        }
                        .padding(.horizontal)

                        // Emisoras Sugeridas
                        if !suggested.isEmpty {
                            Text("Emisoras Sugeridas")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(suggested) { st in
                                        StationHorizontalCard(station: st) {
                                            player.playStation(st, list: suggested)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Escuchado Recientemente
                        if !recents.isEmpty {
                            HStack {
                                Text("Escuchado Recientemente")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Button("Limpiar") {
                                    store.clearRecents()
                                    refreshData()
                                }
                                .font(.caption)
                                .foregroundColor(.neonCyan)
                            }
                            .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recents) { st in
                                        StationHorizontalCard(station: st) {
                                            player.playStation(st, list: recents)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Gestión / Lista Negra
                        Text("Gestión")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal)

                        NavigationLink(destination: BlacklistView()) {
                            HStack {
                                Image(systemName: "nosign")
                                    .foregroundColor(.accentRed)
                                Text("Lista Negra de Emisoras (\(store.blacklistedStations.count))")
                                    .foregroundColor(.textPrimary)
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.textSecondary)
                            }
                            .padding()
                            .background(Color.darkSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    .padding(.bottom, player.currentStation != nil ? 85 : 20)
                }

                if player.currentStation != nil {
                    MiniPlayerDock(onTap: { showFullPlayer = true })
                }
            }
            .navigationTitle("AuraRadio")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchQuery, prompt: "Buscar entre 35.000 emisoras…")
            .overlay {
                if !searchQuery.isEmpty {
                    SearchResultsOverlay(query: searchQuery)
                }
            }
            .sheet(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
            .onAppear { refreshData() }
            .onChange(of: store.blacklistedStations.count) { _ in refreshData() }
            .onChange(of: store.recentIds) { _ in refreshData() }
        }
        .preferredColorScheme(.dark)
    }

    private func refreshData() {
        let blackIds = store.blacklistedIds
        suggested = VRadioDatabase.shared.getSuggestedStations(limit: 12).filter { !blackIds.contains($0.id) }
        recents = VRadioDatabase.shared.getStationsByIds(store.recentIds).filter { !blackIds.contains($0.id) }
    }
}

struct ExploreTile: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 18))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(14)
        .background(Color.darkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct StationHorizontalCard: View {
    let station: Station
    let onTap: () -> Unit

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: station.favicon)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit().padding(6)
                    default:
                        Image(systemName: "radio").foregroundColor(.neonCyan)
                    }
                }
                .frame(width: 110, height: 90)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(station.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(station.subtitleInfo)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 110)
        }
    }
}

struct MiniPlayerDock: View {
    @ObservedObject var player = RadioPlayerService.shared
    let onTap: () -> Unit

    var body: some View {
        if let st = player.currentStation {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: st.favicon)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                    } else {
                        Image(systemName: "radio").foregroundColor(.neonCyan)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(st.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(player.isLoading ? "Conectando…" : (player.liveTitle.isEmpty ? st.subtitleInfo : player.liveTitle))
                        .font(.system(size: 11))
                        .foregroundColor(.neonCyan)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { player.playPrev() }) {
                    Image(systemName: "backward.end.fill").foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 4)

                Button(action: { player.togglePlayPause() }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.darkSurfaceVariant)
                        .clipShape(Circle())
                }

                Button(action: { player.playNext() }) {
                    Image(systemName: "forward.end.fill").foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.darkSurface)
            .onTapGesture { onTap() }
        }
    }
}

struct StationRow: View {
    @ObservedObject var player = RadioPlayerService.shared
    @ObservedObject var store = FavoritesStore.shared
    let station: Station
    let list: [Station]

    var body: some View {
        let isCurrent = player.currentStation?.id == station.id
        let isFav = store.isFavorite(station.id)

        HStack(spacing: 12) {
            AsyncImage(url: URL(string: station.favicon)) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFit().padding(4)
                } else {
                    Image(systemName: "radio").foregroundColor(.neonCyan)
                }
            }
            .frame(width: 46, height: 46)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name)
                    .font(.system(size: 15, weight: isCurrent ? .bold : .semibold))
                    .foregroundColor(isCurrent ? .neonCyan : .textPrimary)
                    .lineLimit(1)
                Text(station.subtitleInfo)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { store.toggleFavorite(station) }) {
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .foregroundColor(isFav ? .accentRed : .textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            player.playStation(station, list: list)
        }
    }
}

struct SearchResultsOverlay: View {
    @ObservedObject var store = FavoritesStore.shared
    let query: String

    var body: some View {
        let blackIds = store.blacklistedIds
        let results = VRadioDatabase.shared.searchStations(query: query, limit: 60).filter { !blackIds.contains($0.id) }
        List(results) { st in
            StationRow(station: st, list: results)
                .listRowBackground(Color.darkBackground)
        }
        .listStyle(.plain)
        .background(Color.darkBackground)
    }
}

struct CountriesGridView: View {
    @ObservedObject var store = FavoritesStore.shared
    private let countries = VRadioDatabase.shared.getCountries()

    var body: some View {
        let recentItems = store.recentCountries.compactMap { name in
            countries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.iso2.caseInsensitiveCompare(name) == .orderedSame }
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !recentItems.isEmpty {
                    Text("🕒 Países Recientes (Máx. 10)")
                        .font(.subheadline.bold())
                        .foregroundColor(.neonCyan)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recentItems) { country in
                                NavigationLink(destination: CountryStationsView(country: country)) {
                                    VStack(spacing: 6) {
                                        AsyncImage(url: country.flagURL) { phase in
                                            if case .success(let img) = phase {
                                                img.resizable().scaledToFit()
                                            }
                                        }
                                        .frame(width: 72, height: 46)
                                        .background(Color.darkSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Text(country.name)
                                            .font(.caption)
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 76)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    Divider()
                }

                Text("Todos los Países (\(countries.count))")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82))], spacing: 12) {
                    ForEach(countries) { country in
                        NavigationLink(destination: CountryStationsView(country: country)) {
                            VStack(spacing: 4) {
                                AsyncImage(url: country.flagURL) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFit()
                                    }
                                }
                                .frame(height: 52)
                                .background(Color.darkSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(country.name)
                                    .font(.caption2)
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color.darkBackground)
        .navigationTitle("Países y Regiones")
    }
}

struct CountryStationsView: View {
    @ObservedObject var store = FavoritesStore.shared
    let country: CountryItem

    var body: some View {
        let blackIds = store.blacklistedIds
        let stations = VRadioDatabase.shared.getStationsByCountry(countryId: country.id, limit: 200)
            .filter { !blackIds.contains($0.id) }
        List(stations) { st in
            StationRow(station: st, list: stations)
                .listRowBackground(Color.darkBackground)
        }
        .listStyle(.plain)
        .background(Color.darkBackground)
        .navigationTitle(country.name)
    }
}

struct CategoriesListView: View {
    private let categories = VRadioDatabase.shared.getCategories()

    var body: some View {
        List(categories) { cat in
            NavigationLink(destination: CategoryStationsView(category: cat)) {
                HStack {
                    Image(systemName: "music.note").foregroundColor(.neonCyan)
                    Text(cat.name).foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(cat.stationsCount)").foregroundColor(.textSecondary).font(.caption)
                }
            }
            .listRowBackground(Color.darkBackground)
        }
        .listStyle(.plain)
        .background(Color.darkBackground)
        .navigationTitle("Categorías")
    }
}

struct CategoryStationsView: View {
    @ObservedObject var store = FavoritesStore.shared
    let category: CategoryItem

    var body: some View {
        let blackIds = store.blacklistedIds
        let stations = VRadioDatabase.shared.getStationsByCategory(categoryId: category.id, limit: 100)
            .filter { !blackIds.contains($0.id) }
        List(stations) { st in
            StationRow(station: st, list: stations)
                .listRowBackground(Color.darkBackground)
        }
        .listStyle(.plain)
        .background(Color.darkBackground)
        .navigationTitle(category.name)
    }
}

struct PopularStationsView: View {
    @ObservedObject var store = FavoritesStore.shared

    var body: some View {
        let blackIds = store.blacklistedIds
        let stations = VRadioDatabase.shared.getPopularStationsByCountryIso(store.detectedCountryIso, limit: 60)
            .filter { !blackIds.contains($0.id) }
        List(stations) { st in
            StationRow(station: st, list: stations)
                .listRowBackground(Color.darkBackground)
        }
        .listStyle(.plain)
        .background(Color.darkBackground)
        .navigationTitle("Emisoras Populares")
    }
}

struct FavoritesListView: View {
    @ObservedObject var store = FavoritesStore.shared

    var body: some View {
        let blackIds = store.blacklistedIds
        let stations = store.favorites.filter { !blackIds.contains($0.id) }
        List(stations) { st in
            StationRow(station: st, list: stations)
                .listRowBackground(Color.darkBackground)
        }
        .listStyle(.plain)
        .background(Color.darkBackground)
        .navigationTitle("Favoritas")
    }
}

struct BlacklistView: View {
    @ObservedObject var store = FavoritesStore.shared

    var body: some View {
        let grouped = Dictionary(grouping: store.blacklistedStations) {
            $0.country.isEmpty ? "Sin País Especificado" : $0.country
        }
        let sortedKeys = grouped.keys.sorted()

        List {
            if store.blacklistedStations.isEmpty {
                Text("No hay emisoras en Lista Negra.")
                    .foregroundColor(.textSecondary)
                    .listRowBackground(Color.darkBackground)
            } else {
                ForEach(sortedKeys, id: \.self) { country in
                    Section(header: Text(country).foregroundColor(.neonCyan)) {
                        ForEach(grouped[country] ?? []) { st in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(st.name).foregroundColor(.textPrimary).font(.subheadline.bold())
                                    Text("\(st.streamFormatBadge) • \(st.url)")
                                        .foregroundColor(.textSecondary)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Restaurar") {
                                    store.removeFromBlacklist(st.id)
                                }
                                .buttonStyle(.bordered)
                                .tint(.neonCyan)
                            }
                            .listRowBackground(Color.darkSurface)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.darkBackground)
        .navigationTitle("Lista Negra")
        .toolbar {
            if !store.blacklistedStations.isEmpty {
                ShareLink(item: store.exportBlacklistTxt()) {
                    Label("Exportar .txt", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
