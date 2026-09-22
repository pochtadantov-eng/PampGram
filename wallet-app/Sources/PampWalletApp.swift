import SwiftUI

@main
struct PampWalletApp: App {
    @StateObject private var store = WalletStore()

    var body: some Scene {
        WindowGroup {
            WalletHomeView()
                .environmentObject(store)
        }
    }
}
