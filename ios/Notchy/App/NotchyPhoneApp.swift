import SwiftUI
import UIKit

// MARK: - Notchy for iPhone

@main
struct NotchyPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @StateObject private var store = PhoneStore.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onOpenURL { store.handle(url: $0) }
        }
        .onChange(of: phase) { _, p in store.scenePhase(p) }
    }
}

final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated {
            Notifications.shared.setUp()
            _ = SoundEngine.shared
            #if DEBUG
            DemoSeed.applyIfAsked()
            #endif
        }
        return true
    }
}

struct RootView: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        Group {
            if store.computer == nil {
                PairingView()
            } else {
                MainView()
            }
        }
        .modifier(PairConfirm())
        .animation(.easeInOut(duration: 0.3), value: store.computer)
    }
}
