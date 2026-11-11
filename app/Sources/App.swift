import SwiftUI

@main
struct MaiPanelShellApp: App {
    var body: some Scene {
        WindowGroup {
            ShellView()
                .preferredColorScheme(.dark)
        }
    }
}
