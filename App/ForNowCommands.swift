import AppKit
import SwiftUI

struct ForNowCommands: Commands {
  let environment: AppEnvironment

  var body: some Commands {
    CommandGroup(after: .appSettings) {
      Button("Toggle Window") {
        environment.toggleWindow()
      }
      .keyboardShortcut("o", modifiers: .command)

      Button("Toggle Pin") {
        Task { try? await environment.togglePin() }
      }
      .keyboardShortcut("p", modifiers: .command)

      Button("Close Window") {
        environment.closeWindow()
      }
      .keyboardShortcut("w", modifiers: .command)
    }

    CommandGroup(after: .textEditing) {
      Button("Stop AutoPaste") {
        environment.stopAutoPaste(.escape)
      }
      .keyboardShortcut(.cancelAction)
      .disabled(!environment.autoPasteModel.isActive)

      Divider()
      Button("Paste Without Transformations") {
        NSApp.sendAction(Selector(("pasteRaw:")), to: nil, from: nil)
      }
      .keyboardShortcut("v", modifiers: [.command, .shift])

      Button("Toggle Comment") {
        NSApp.sendAction(Selector(("toggleComment:")), to: nil, from: nil)
      }
      .keyboardShortcut("/", modifiers: .command)

      Divider()
      Button("Search Notes") {
        environment.openSearch()
      }
      .keyboardShortcut("f", modifiers: .command)

      Button("Find and Replace") {
        environment.openFindReplace()
      }
      .keyboardShortcut("f", modifiers: [.command, .shift])

      Button("Previous Note") {
        Task { try? await environment.noteSession.navigate(.previous) }
      }
      .keyboardShortcut("[", modifiers: .command)

      Button("Next Note") {
        Task { try? await environment.noteSession.navigate(.next) }
      }
      .keyboardShortcut("]", modifiers: .command)

      Button("Newest Note") {
        Task { try? await environment.noteSession.jumpToNewest() }
      }
      .keyboardShortcut("1", modifiers: .command)

      Button("Promote Note") {
        Task { try? await environment.noteSession.promoteCurrent() }
      }
      .keyboardShortcut("1", modifiers: [.command, .shift])

      Button("Delete Note") {
        Task { try? await environment.deleteCurrentNote() }
      }
      .keyboardShortcut("d", modifiers: .command)
    }
  }
}
