import AppKit
import SwiftUI
import SwiftData

private final class BurritoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = BurritoAppFeedback.shared
    }
}

@main
struct burritoApp: App {
    @NSApplicationDelegateAdaptor(BurritoAppDelegate.self) private var appDelegate

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Note.self, Folder.self, NoteTemplate.self)
        } catch {
            fatalError("Burrito could not create its local data store: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .defaultSize(width: 1_180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            BurritoCommands()
        }
    }
}
