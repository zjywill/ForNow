import AppKit
import SwiftUI

@MainActor
final class WindowSpikeAppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: WindowSpikeCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let coordinator = WindowSpikeCoordinator()
    self.coordinator = coordinator
    coordinator.start()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    coordinator?.applicationDidBecomeActive()
  }

  func applicationDidResignActive(_ notification: Notification) {
    coordinator?.applicationDidResignActive()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func toggleWindowCommand() {
    coordinator?.toggleWindowCommand()
  }

  func togglePinCommand() {
    coordinator?.togglePinCommand()
  }
}

@main
struct WindowSpikeApp: App {
  @NSApplicationDelegateAdaptor(WindowSpikeAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(after: .appSettings) {
        Button("Toggle Window") {
          appDelegate.toggleWindowCommand()
        }
        .keyboardShortcut("o", modifiers: .command)

        Button("Pin Window") {
          appDelegate.togglePinCommand()
        }
        .keyboardShortcut("p", modifiers: .command)
      }
    }
  }
}
