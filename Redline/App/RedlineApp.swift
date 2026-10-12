import SwiftUI

@main
struct RedlineApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Redline") {
            ContentView()
                .environment(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 780, height: 940)
    }
}
