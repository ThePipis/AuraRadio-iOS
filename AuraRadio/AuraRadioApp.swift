import SwiftUI

@main
struct AuraRadioApp: App {
    init() {
        _ = RadioPlayerService.shared
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
