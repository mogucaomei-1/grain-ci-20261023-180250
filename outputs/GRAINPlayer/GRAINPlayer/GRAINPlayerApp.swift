import SwiftUI

@main
struct GRAINPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onAppear(perform: GrainHaptics.prepare)
        }
    }
}
