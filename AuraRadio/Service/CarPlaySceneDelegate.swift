import Foundation
import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupNowPlayingButtons()
        interfaceController.setRootTemplate(buildTabBarTemplate(), animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func setupNowPlayingButtons() {
        let favButton = CPNowPlayingImageButton(image: UIImage(systemName: "heart.fill") ?? UIImage()) { _ in
            if let current = RadioPlayerService.shared.currentStation {
                FavoritesStore.shared.toggleFavorite(current)
            }
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([favButton])
    }

    private func buildTabBarTemplate() -> CPTabBarTemplate {
        let favTab = buildStationsListTemplate(title: "Favoritas", systemImage: "star.fill", stations: filteredFavorites())
        let countriesTab = buildCountriesTemplate()
        let popularTab = buildStationsListTemplate(
            title: "Populares",
            systemImage: "flame.fill",
            stations: VRadioDatabase.shared.getPopularStationsByCountryIso(FavoritesStore.shared.detectedCountryIso, limit: 60)
                .filter { !FavoritesStore.shared.blacklistedIds.contains($0.id) }
        )
        let recents = VRadioDatabase.shared.getStationsByIds(FavoritesStore.shared.recentIds)
            .filter { !FavoritesStore.shared.blacklistedIds.contains($0.id) }
        let recentsTab = buildStationsListTemplate(title: "Recientes", systemImage: "clock.fill", stations: recents)

        return CPTabBarTemplate(templates: [favTab, countriesTab, popularTab, recentsTab])
    }

    private func filteredFavorites() -> [Station] {
        let blackIds = FavoritesStore.shared.blacklistedIds
        return FavoritesStore.shared.favorites.filter { !blackIds.contains($0.id) }
    }

    private func buildStationsListTemplate(title: String, systemImage: String, stations: [Station]) -> CPListTemplate {
        let items = stations.map { st -> CPListItem in
            let item = CPListItem(text: st.name, detailText: st.subtitleInfo)
            item.handler = { [weak self] _, completion in
                RadioPlayerService.shared.playStation(st, list: stations)
                self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: title, sections: [CPListSection(items: items)])
        template.tabImage = UIImage(systemName: systemImage)
        return template
    }

    private func buildCountriesTemplate() -> CPListTemplate {
        let allCountries = VRadioDatabase.shared.getCountries()
        let recentNames = FavoritesStore.shared.recentCountries
        let recentCountries = recentNames.compactMap { rName in
            allCountries.first { $0.name.caseInsensitiveCompare(rName) == .orderedSame || $0.iso2.caseInsensitiveCompare(rName) == .orderedSame }
        }
        let recentIds = Set(recentCountries.map { $0.id })
        let ordered = recentCountries + allCountries.filter { !recentIds.contains($0.id) }

        let items = ordered.map { country -> CPListItem in
            let item = CPListItem(text: country.name, detailText: "\(country.stationsCount) emisoras")
            item.handler = { [weak self] _, completion in
                let blackIds = FavoritesStore.shared.blacklistedIds
                let stations = VRadioDatabase.shared.getStationsByCountry(countryId: country.id, limit: 200)
                    .filter { !blackIds.contains($0.id) }
                let subList = self?.buildStationsListTemplate(title: country.name, systemImage: "globe", stations: stations)
                if let subList = subList {
                    self?.interfaceController?.pushTemplate(subList, animated: true, completion: nil)
                }
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: "Países", sections: [CPListSection(items: items)])
        template.tabImage = UIImage(systemName: "globe")
        return template
    }
}
