import SwiftUI

@main
struct MappledownApp: App {
    @StateObject private var library = Library()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(settings)
                .tint(Color("AccentColor"))
                .onOpenURL { url in
                    // "Open in Mappledown" from the Files app, or tapping a .md file.
                    guard url.isFileURL else { return }
                    library.close()
                    library.open(url, defaultMode: settings.defaultMode)
                }
        }
    }
}
