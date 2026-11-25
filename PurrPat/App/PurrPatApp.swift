import SwiftUI

@main
struct PurrPatApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var purchases = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            PetScreen()
                .environmentObject(settings)
                .environmentObject(purchases)
                .tint(Color("AccentColor"))
        }
    }
}
