import SwiftUI
import UserNotifications

@main
@MainActor
struct MyApp: App {
    @StateObject private var store = VaultStore()
    init() {
        VaultAppearance.configure()
        UNUserNotificationCenter.current().delegate = VaultNotificationDelegate.shared
    }
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
    }
}
