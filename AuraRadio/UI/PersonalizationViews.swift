import SwiftUI

// MARK: - Redes de Emisoras
struct NetworksGridView: View {
    @State private var networks: [NetworkItem] = []
    @State private var search = ""

    var filtered: [NetworkItem] {
        if search.isEmpty { return networks }
        return networks.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            ForEach(filtered) { net in
                NavigationLink(destination: NetworkStationsView(network: net)) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.deepViolet.opacity(0.25))
                                .frame(width: 40, height: 40)
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.neonCyan)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(net.name)
                                .foregroundColor(.textPrimary)
                                .fontWeight(.semibold)
                            Text("\(net.stationsCount) emisoras")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .listRowBackground(Color.darkSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.darkBackground)
        .searchable(text: $search, prompt: "Buscar red de emisoras")
        .navigationTitle("Redes de Emisoras")
        .onAppear {
            if networks.isEmpty {
                networks = VRadioDatabase.shared.getNetworks()
            }
        }
    }
}

struct NetworkStationsView: View {
    let network: NetworkItem
    @ObservedObject var store = FavoritesStore.shared
    @State private var stations: [Station] = []

    var body: some View {
        let blackIds = store.blacklistedIds
        let visible = stations.filter { !blackIds.contains($0.id) }
        List {
            ForEach(visible) { st in
                StationRow(station: st, list: visible)
                    .listRowBackground(Color.darkBackground)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.darkBackground)
        .navigationTitle(network.name)
        .onAppear {
            if stations.isEmpty {
                stations = VRadioDatabase.shared.getStationsByNetwork(networkId: network.id, limit: 150)
            }
        }
    }
}

// MARK: - Historial de Títulos
struct SongHistoryView: View {
    @ObservedObject var store = FavoritesStore.shared

    var body: some View {
        ZStack {
            Color.darkBackground.ignoresSafeArea()
            if store.songHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.textSecondary)
                    Text("Sin historial de títulos todavía")
                        .foregroundColor(.textPrimary)
                        .fontWeight(.semibold)
                    Text("Los nombres de canciones detectados en vivo aparecerán aquí.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List {
                    ForEach(store.songHistory) { item in
                        let saved = store.isSongSaved(item)
                        HStack(spacing: 12) {
                            Image(systemName: "music.note")
                                .foregroundColor(.neonCyan)
                                .frame(width: 36, height: 36)
                                .background(Color.darkSurfaceVariant)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .foregroundColor(.textPrimary)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text("\(item.stationName)")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(action: { store.toggleSongInCollection(item) }) {
                                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                                    .foregroundColor(saved ? .neonCyan : .textSecondary)
                            }
                        }
                        .listRowBackground(Color.darkSurface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Historial de Títulos")
        .toolbar {
            if !store.songHistory.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Limpiar") { store.clearSongHistory() }
                        .foregroundColor(.accentRed)
                }
            }
        }
    }
}

// MARK: - Colección de Títulos
struct SongCollectionView: View {
    @ObservedObject var store = FavoritesStore.shared

    var body: some View {
        ZStack {
            Color.darkBackground.ignoresSafeArea()
            if store.songCollection.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48))
                        .foregroundColor(.textSecondary)
                    Text("Tu colección de títulos está vacía")
                        .foregroundColor(.textPrimary)
                        .fontWeight(.semibold)
                    Text("Guarda canciones desde el Historial de Títulos.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            } else {
                List {
                    ForEach(store.songCollection) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.neonCyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .foregroundColor(.textPrimary)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text(item.stationName)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Button(action: { store.toggleSongInCollection(item) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.accentRed)
                            }
                        }
                        .listRowBackground(Color.darkSurface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Colección de Títulos")
    }
}

// MARK: - Emisoras de Usuario
struct UserStationsView: View {
    @ObservedObject var store = FavoritesStore.shared
    @ObservedObject var player = RadioPlayerService.shared
    @State private var showAddSheet = false
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        ZStack {
            Color.darkBackground.ignoresSafeArea()
            if store.userStations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 48))
                        .foregroundColor(.textSecondary)
                    Text("Sin emisoras personalizadas")
                        .foregroundColor(.textPrimary)
                        .fontWeight(.semibold)
                    Button("Agregar Emisora") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.deepViolet)
                }
            } else {
                List {
                    ForEach(store.userStations) { st in
                        HStack {
                            StationRow(station: st, list: store.userStations)
                            Button(action: { store.removeUserStation(st.id) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.accentRed)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color.darkBackground)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Emisoras de Usuario")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                Form {
                    TextField("Nombre de la emisora", text: $name)
                    TextField("URL del stream (https://...)", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                .navigationTitle("Nueva Emisora")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showAddSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar") {
                            store.addUserStation(name: name, url: url)
                            name = ""
                            url = ""
                            showAddSheet = false
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Temporizador de Sueño
struct SleepTimerSheet: View {
    @ObservedObject var player = RadioPlayerService.shared
    @Environment(\.dismiss) private var dismiss
    private let options = [5, 10, 15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            List {
                if player.sleepTimerRemainingMinutes > 0 {
                    Section {
                        HStack {
                            Text("Apagado programado en \(player.sleepTimerRemainingMinutes) min")
                                .foregroundColor(.neonCyan)
                                .fontWeight(.semibold)
                            Spacer()
                            Button("Cancelar") {
                                player.cancelSleepTimer()
                                dismiss()
                            }
                            .foregroundColor(.accentRed)
                        }
                    }
                    .listRowBackground(Color.darkSurface)
                }

                Section("Seleccionar duración") {
                    ForEach(options, id: \.self) { mins in
                        Button(action: {
                            player.startSleepTimer(minutes: mins)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundColor(.neonCyan)
                                Text("\(mins) minutos")
                                    .foregroundColor(.textPrimary)
                            }
                        }
                        .listRowBackground(Color.darkSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.darkBackground)
            .navigationTitle("Temporizador de Sueño")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Vista Informativa para Módulos Auxiliares
struct FeatureStatusView: View {
    let title: String
    let icon: String
    let description: String

    var body: some View {
        ZStack {
            Color.darkBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundColor(.neonCyan)
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.textPrimary)
                Text(description)
                    .font(.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Búsqueda Rápida (Botón Lupa Superior)
struct QuickSearchSheet: View {
    @ObservedObject var store = FavoritesStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var results: [Station] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let blackIds = store.blacklistedIds
        return VRadioDatabase.shared.searchStations(query: q, limit: 60).filter { !blackIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBackground.ignoresSafeArea()
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 42))
                            .foregroundColor(.textSecondary)
                        Text("Escribe al menos 2 letras para buscar")
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    List {
                        ForEach(results) { st in
                            StationRow(station: st, list: results)
                                .listRowBackground(Color.darkBackground)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Buscar Emisoras")
            .searchable(text: $query, prompt: "Nombre, país o género…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Resolución de Problemas (Menú 3 Puntos Superior)
struct TroubleshootingSheet: View {
    @ObservedObject var player = RadioPlayerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Diagnóstico del Motor de Audio") {
                    HStack {
                        Text("Estado AVPlayer")
                        Spacer()
                        Text(player.isPlaying ? "Reproduciendo en directo" : (player.isLoading ? "Conectando…" : "En espera"))
                            .foregroundColor(.neonCyan)
                    }
                    HStack {
                        Text("Filtro AdsWizz / Mediastream")
                        Spacer()
                        Text("ACTIVO (Sin publicidad)")
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("CarPlay & AirPlay")
                        Spacer()
                        Text("Habilitado")
                            .foregroundColor(.textSecondary)
                    }
                    if let st = player.currentStation {
                        HStack {
                            Text("Emisora activa")
                            Spacer()
                            Text(st.name)
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }
                .listRowBackground(Color.darkSurface)

                if let st = player.currentStation {
                    Section {
                        Button(action: {
                            player.playStation(st, list: player.playlist)
                            dismiss()
                        }) {
                            Label("Reconectar emisora actual", systemImage: "arrow.clockwise")
                                .foregroundColor(.neonCyan)
                        }
                    }
                    .listRowBackground(Color.darkSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.darkBackground)
            .navigationTitle("Resolución de Problemas")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

