import SwiftUI

@main
struct GRAINPlayerApp: App {
    @AppStorage("appTheme") private var appTheme: String = "system"

    private var activeColorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(activeColorScheme)
                .onAppear(perform: GrainHaptics.prepare)
        }
    }
}
