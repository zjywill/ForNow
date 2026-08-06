import SwiftUI

@main
struct ForNowApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView(environment: appDelegate.environment)
    }
    .commands {
      ForNowCommands(environment: appDelegate.environment)
    }
  }
}
