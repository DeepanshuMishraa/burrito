import Foundation
import SwiftUI

extension Notification.Name {
    static let burritoNewRecording = Notification.Name("burrito.new-recording")
    static let burritoToggleRecording = Notification.Name("burrito.toggle-recording")
    static let burritoNewFolder = Notification.Name("burrito.new-folder")
    static let burritoFind = Notification.Name("burrito.find")
    static let burritoExportMarkdown = Notification.Name("burrito.export-markdown")
}

struct BurritoCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recording") {
                NotificationCenter.default.post(name: .burritoNewRecording, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                NotificationCenter.default.post(name: .burritoNewFolder, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Button("Start/Stop Recording") {
                NotificationCenter.default.post(name: .burritoToggleRecording, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Export Markdown…") {
                NotificationCenter.default.post(name: .burritoExportMarkdown, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowController.show()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Button("Find") {
                NotificationCenter.default.post(name: .burritoFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
