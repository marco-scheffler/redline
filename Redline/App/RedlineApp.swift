import SwiftUI

@main
struct RedlineApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Redline") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 780, height: 940)
    }
}
