import SwiftUI

struct HomeView: View {
    @ObservedObject var player = RadioPlayerService.shared
    @ObservedObject var store = FavoritesStore.shared

    @State private var path = NavigationPath()
    @State private var searchQuery = ""
    @State private var showFullPlayer = false
    @State private var showDrawer = false
    @State private var showSleepTimer = false
    @State private var showTroubleshooting = false
    @State private var showQuickSearch = false
    @State private var suggested: [Station] = []
    @State private var recents: [Station] = []

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                NavigationStack(path: $path) {
                    ZStack {
                        Color.darkBackground.ignoresSafeArea()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                // 1. Explorar (5 opciones como en Android, sin texto truncado)
                                Text("Explorar")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    NavigationLink(value: AppRoute.countries) {
                                        ExploreTile(icon: "globe", title: "Países y Regiones", color: .neonCyan)
                                    }
                                    NavigationLink(value: AppRoute.categories) {
                                        ExploreTile(icon: "music.note.list", title: "Categorías", color: .green)
                                    }
                                    NavigationLink(value: AppRoute.networks) {
                                        ExploreTile(icon: "antenna.radiowaves.left.and.right", title: "Redes de Emisoras", color: .purple)
                                    }
                                    NavigationLink(value: AppRoute.popular) {
                                        ExploreTile(icon: "flame.fill", title: "Emisoras Populares", color: .orange)
                                    }
                                    NavigationLink(value: AppRoute.favorites) {
                                        ExploreTile(icon: "heart.fill", title: "Mis Favoritas", color: .accentRed)
                                    }
                                }
                                .padding(.horizontal)

                                // 2. Emisoras Sugeridas
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

                                // 3. Personalización (2x5 grilla igual que Android)
                                Text("Personalización")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal)

                                VStack(spacing: 6) {
                                    HStack(spacing: 8) {
                                        PersonalizationTile(icon: "heart.fill", title: "Favoritas", color: .accentRed) {
                                            path.append(AppRoute.favorites)
                                        }
                                        PersonalizationTile(icon: "person.wave.2", title: "Emisoras de Usuario", color: .neonCyan) {
                                            path.append(AppRoute.userStations)
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        PersonalizationTile(icon: "record.circle", title: "Grabaciones", color: .orange) {
                                            path.append(AppRoute.recordings)
                                        }
                                        PersonalizationTile(icon: "alarm", title: "Despertadores", color: .yellow) {
                                            path.append(AppRoute.alarms)
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        PersonalizationTile(icon: "timer", title: "Temporizador de Sueño", color: .neonCyan) {
                                            showSleepTimer = true
                                        }
                                        PersonalizationTile(icon: "calendar.badge.clock", title: "Horarios", color: .green) {
                                            path.append(AppRoute.alarms)
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        PersonalizationTile(icon: "books.vertical", title: "Colección de Títulos", color: .purple) {
                                            path.append(AppRoute.songCollection)
                                        }
                                        PersonalizationTile(icon: "music.note.list", title: "Historial de Títulos", color: .neonCyan) {
                                            path.append(AppRoute.songHistory)
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        PersonalizationTile(icon: "slider.vertical.3", title: "Ecualizador de Audio", color: .green) {
                                            path.append(AppRoute.equalizer)
                                        }
                                        PersonalizationTile(icon: "gearshape.fill", title: "Ajustes", color: .textSecondary) {
                                            path.append(AppRoute.settings)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color.darkSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)

                                // 4. Escuchado Recientemente
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

                                // 5. Uso de Datos (igual que Android con menú de reinicio)
                                HStack {
                                    Text("Uso de Datos")
                                        .font(.headline)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Menu {
                                        Button(role: .destructive, action: { store.resetDataUsage() }) {
                                            Label("Eliminar las métricas", systemImage: "arrow.counterclockwise")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .foregroundColor(.textSecondary)
                                            .padding(6)
                                    }
                                }
                                .padding(.horizontal)

                                HStack {
                                    VStack(spacing: 4) {
                                        Text("WiFi")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                        Text(FavoritesStore.formatBytes(store.wifiBytes))
                                            .font(.headline)
                                            .foregroundColor(.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity)

                                    Divider()
                                        .frame(height: 34)
                                        .background(Color.darkSurfaceVariant)

                                    VStack(spacing: 4) {
                                        Text("Datos Móviles")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                        Text(FavoritesStore.formatBytes(store.mobileBytes))
                                            .font(.headline)
                                            .foregroundColor(.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .padding(.vertical, 14)
                                .background(Color.darkSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal)

                                // 6. Gestión / Lista Negra
                                Text("Gestión")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal)

                                NavigationLink(value: AppRoute.blacklist) {
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
                        }
                    }
                    .navigationTitle("AuraRadio")
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showDrawer.toggle()
                                }
                            }) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                            }
                        }

                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            AirPlayPickerButton()
                                .frame(width: 26, height: 26)

                            Button(action: { showQuickSearch = true }) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.textPrimary)
                            }

                            Button(action: { path.append(AppRoute.favorites) }) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.accentRed)
                            }

                            Menu {
                                Button(action: { path.append(AppRoute.alarms) }) {
                                    Label("Despertadores", systemImage: "alarm")
                                }
                                Button(action: { showSleepTimer = true }) {
                                    Label("Temporizador de Sueño", systemImage: "timer")
                                }
                                Button(action: { path.append(AppRoute.alarms) }) {
                                    Label("Horarios", systemImage: "clock")
                                }
                                Button(action: { showTroubleshooting = true }) {
                                    Label("Resolución de Problemas", systemImage: "wrench.and.screwdriver")
                                }
                                Divider()
                                Button(action: { path.append(AppRoute.settings) }) {
                                    Label("Ajustes", systemImage: "gearshape")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .rotationEffect(.degrees(90))
                                    .foregroundColor(.textPrimary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .searchable(text: $searchQuery, prompt: "Buscar entre 35.000 emisoras…")
                    .overlay {
                        if !searchQuery.isEmpty {
                            SearchResultsOverlay(query: searchQuery)
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .countries: CountriesGridView()
                        case .categories: CategoriesListView()
                        case .networks: NetworksGridView()
                        case .popular: PopularStationsView()
                        case .favorites: FavoritesListView()
                        case .recent: RecentStationsView()
                        case .blacklist: BlacklistView()
                        case .songHistory: SongHistoryView()
                        case .songCollection: SongCollectionView()
                        case .userStations: UserStationsView()
                        case .recordings:
                            FeatureStatusView(title: "Grabaciones", icon: "record.circle", description: "Las grabaciones de emisoras en directo estarán disponibles próximamente en iOS.")
                        case .alarms:
                            FeatureStatusView(title: "Despertadores y Horarios", icon: "alarm", description: "Programa alarmas con tu emisora favorita para despertar con radio en vivo.")
                        case .equalizer:
                            FeatureStatusView(title: "Ecualizador de Audio", icon: "slider.vertical.3", description: "Audio optimizado con perfil HD nativo de iOS y soporte AirPlay.")
                        case .settings:
                            FeatureStatusView(title: "Ajustes de AuraRadio", icon: "gearshape.fill", description: "Versión 2.10.1 iOS • Supresor de publicidad AdsWizz activo • CarPlay y AirPlay habilitados.")
                        }
                    }
                }

                // MiniPlayerDock SIEMPRE visible en TODAS las pantallas cuando hay emisora activa
                if player.currentStation != nil {
                    MiniPlayerDock(onTap: { showFullPlayer = true })
                }
            }

            // Menú Hamburguesa Lateral (Drawer)
            if showDrawer {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showDrawer = false
                        }
                    }

                DrawerSidebarView(
                    onSelectRoute: { route in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showDrawer = false
                        }
                        if let route = route {
                            path = NavigationPath([route])
                        } else {
                            path = NavigationPath()
                        }
                    },
                    onSleepTimer: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showDrawer = false
                        }
                        showSleepTimer = true
                    }
                )
                .transition(.move(edge: .leading))
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerView()
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet()
        }
        .sheet(isPresented: $showQuickSearch) {
            QuickSearchSheet()
        }
        .sheet(isPresented: $showTroubleshooting) {
            TroubleshootingSheet()
        }
        .onAppear { refreshData() }
        .onChange(of: store.blacklistedStations.count) { _ in refreshData() }
        .onChange(of: store.recentIds) { _ in refreshData() }
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
                .frame(width: 22)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color.darkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PersonalizationTile: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.darkSurfaceVariant.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct DrawerSidebarView: View {
    let onSelectRoute: (AppRoute?) -> Void
    let onSleepTimer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.deepViolet)
                        .frame(width: 42, height: 42)
                    Image(systemName: "radio.fill")
                        .foregroundColor(.neonCyan)
                        .font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AuraRadio")
                        .font(.headline.bold())
                        .foregroundColor(.textPrimary)
                    Text("HD Global Streaming")
                        .font(.caption)
                        .foregroundColor(.neonCyan)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)

            Divider().background(Color.darkSurfaceVariant)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    DrawerItem(icon: "speaker.wave.2.fill", title: "Ahora Escuchando") { onSelectRoute(nil) }
                    DrawerItem(icon: "clock.arrow.circlepath", title: "Escuchado Recientemente") { onSelectRoute(.recent) }

                    Divider().background(Color.darkSurfaceVariant).padding(.vertical, 6)

                    DrawerItem(icon: "record.circle", title: "Grabaciones") { onSelectRoute(.recordings) }
                    DrawerItem(icon: "person.wave.2", title: "Emisoras de Usuario") { onSelectRoute(.userStations) }
                    DrawerItem(icon: "heart.fill", title: "Favoritas") { onSelectRoute(.favorites) }
                    DrawerItem(icon: "books.vertical", title: "Colección de Títulos") { onSelectRoute(.songCollection) }
                    DrawerItem(icon: "music.note.list", title: "Historial de Títulos") { onSelectRoute(.songHistory) }

                    Divider().background(Color.darkSurfaceVariant).padding(.vertical, 6)

                    DrawerItem(icon: "globe", title: "Países y Regiones") { onSelectRoute(.countries) }
                    DrawerItem(icon: "music.quarternote.3", title: "Categorías") { onSelectRoute(.categories) }
                    DrawerItem(icon: "antenna.radiowaves.left.and.right", title: "Redes de Emisoras") { onSelectRoute(.networks) }
                    DrawerItem(icon: "flame.fill", title: "Emisoras Populares") { onSelectRoute(.popular) }
                    DrawerItem(icon: "nosign", title: "Lista Negra") { onSelectRoute(.blacklist) }

                    Divider().background(Color.darkSurfaceVariant).padding(.vertical, 6)

                    DrawerItem(icon: "alarm", title: "Despertadores") { onSelectRoute(.alarms) }
                    DrawerItem(icon: "timer", title: "Temporizador de Sueño") { onSleepTimer() }
                    DrawerItem(icon: "slider.vertical.3", title: "Ecualizador de Audio") { onSelectRoute(.equalizer) }
                    DrawerItem(icon: "gearshape.fill", title: "Ajustes") { onSelectRoute(.settings) }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
        .background(Color.darkSurface.ignoresSafeArea())
    }
}

struct DrawerItem: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundColor(.neonCyan)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}

struct RecentStationsView: View {
    @ObservedObject var store = FavoritesStore.shared

    var body: some View {
        let blackIds = store.blacklistedIds
        let visible = VRadioDatabase.shared.getStationsByIds(store.recentIds).filter { !blackIds.contains($0.id) }
        List {
            ForEach(visible) { st in
                StationRow(station: st, list: visible)
                    .listRowBackground(Color.darkBackground)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.darkBackground)
        .navigationTitle("Escuchado Recientemente")
    }
}

struct StationHorizontalCard: View {
    let station: Station
    let onTap: () -> Void

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
    let onTap: () -> Void

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

struct FlagImageCache {
    static let memory = NSCache<NSString, UIImage>()
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 60 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 8.0
        return URLSession(configuration: config)
    }()
}

struct FlagImageView: View {
    let country: CountryItem
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.darkSurface
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(country.flagEmoji)
                    .font(.system(size: 34))
            }
        }
        .onAppear { loadFlag(attempt: 1) }
    }

    private func loadFlag(attempt: Int) {
        guard loadedImage == nil, let url = country.flagURL else { return }
        let key = url.absoluteString as NSString
        if let cached = FlagImageCache.memory.object(forKey: key) {
            loadedImage = cached
            return
        }
        FlagImageCache.session.dataTask(with: url) { data, _, _ in
            if let data = data, let img = UIImage(data: data) {
                FlagImageCache.memory.setObject(img, forKey: key)
                DispatchQueue.main.async {
                    loadedImage = img
                }
            } else if attempt < 3 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Double(attempt) * 0.6) {
                    loadFlag(attempt: attempt + 1)
                }
            }
        }.resume()
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
                                        FlagImageView(country: country)
                                            .frame(width: 72, height: 46)
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
                                FlagImageView(country: country)
                                    .frame(height: 52)
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
