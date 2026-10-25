import SwiftUI

@main
struct GRAINApp: App {
    @StateObject private var editor = EditorViewModel()
    @AppStorage("didCompletePermissionOnboarding") private var didCompletePermissionOnboarding = false
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system

    init() {
        // 「从文件导入」默认改为关闭：老版本已隐式启用过，这里只迁移一次，
        // 之后用户仍可在设置里手动打开。
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didMigrateFileImportDefaultOff") {
            defaults.set(false, forKey: "showFileImportButton")
            defaults.set(true, forKey: "didMigrateFileImportDefaultOff")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if didCompletePermissionOnboarding {
                    RootView()
                        .environmentObject(editor)
                } else {
                    PermissionOnboardingView {
                        didCompletePermissionOnboarding = true
                    }
                    .preferredColorScheme(appearanceMode.colorScheme)
                }
            }
            .onAppear(perform: GrainHaptics.prepare)
        }
    }
}
