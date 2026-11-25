import SwiftUI

@main
struct AuraRadioApp: App {
    @StateObject private var player = RadioPlayerService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _ = LocalAdStrippingProxy.shared
        _ = RadioPlayerService.shared
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .onAppear {
                    player.ensureAutoPlayOnLaunch()
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        player.handleAppDidBecomeActive()
                    case .background:
                        player.handleAppDidEnterBackground()
                    default:
                        break
                    }
                }
        }
    }
}
