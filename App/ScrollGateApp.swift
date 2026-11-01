import SwiftUI

@main
struct ScrollGateApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environmentObject(model)
        }
    }
}
