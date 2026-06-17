import SwiftUI

@main
struct MacBookStressTestApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacBook Stress Test") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 780, height: 940)
    }
}
