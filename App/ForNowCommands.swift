import AppKit
import SwiftUI

struct ForNowCommands: Commands {
  @ObservedObject private var environment: AppEnvironment

  init(environment: AppEnvironment) {
    _environment = ObservedObject(wrappedValue: environment)
  }

  var body: some Commands {
    CommandGroup(after: .appSettings) {
      Button("Toggle Window") {
        environment.toggleWindow()
      }
      .keyboardShortcut("o", modifiers: .command)

      Button("Toggle Pin") {
        Task { try? await environment.togglePin() }
      }
      .quickActionShortcut(.togglePin, settings: environment.quickActionSettings)

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
      .quickActionShortcut(.searchNotes, settings: environment.quickActionSettings)

      Button("Find and Replace") {
        environment.openFindReplace()
      }
      .keyboardShortcut("f", modifiers: [.command, .shift])

      Button("Previous Note") {
        Task { try? await environment.noteSession.navigate(.previous) }
      }
      .quickActionShortcut(.previousNote, settings: environment.quickActionSettings)

      Button("Next Note") {
        Task { try? await environment.noteSession.navigate(.next) }
      }
      .quickActionShortcut(.nextNote, settings: environment.quickActionSettings)

      Button("Newest Note") {
        Task { try? await environment.noteSession.jumpToNewest() }
      }
      .quickActionShortcut(.newestNote, settings: environment.quickActionSettings)

      Button("New Note") {
        Task { try? await environment.noteSession.createNewNote() }
      }
      .quickActionShortcut(.newNote, settings: environment.quickActionSettings)

      Button("Promote Note") {
        Task { try? await environment.noteSession.promoteCurrent() }
      }
      .quickActionShortcut(.promoteNote, settings: environment.quickActionSettings)

      Button("Delete Note") {
        Task { try? await environment.deleteCurrentNote() }
      }
      .quickActionShortcut(.deleteNote, settings: environment.quickActionSettings)

      Divider()
      Button("Increase Text Size") {
        Task { try? await environment.stepTextSize(by: 1) }
      }
      .quickActionShortcut(.increaseTextSize, settings: environment.quickActionSettings)

      Button("Decrease Text Size") {
        Task { try? await environment.stepTextSize(by: -1) }
      }
      .quickActionShortcut(.decreaseTextSize, settings: environment.quickActionSettings)
    }
  }
}

extension View {
  fileprivate func quickActionShortcut(
    _ action: QuickAction,
    settings: QuickActionSettings
  ) -> some View {
    let shortcut = settings[action]
    return keyboardShortcut(
      shortcut.keyEquivalent,
      modifiers: shortcut.modifiers.eventModifiers
    )
  }
}
