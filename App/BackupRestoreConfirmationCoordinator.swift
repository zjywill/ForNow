import AppKit

@MainActor
final class BackupRestoreConfirmationCoordinator {
  func requestConfirmation(for backup: ManagedBackup) async -> Bool {
    guard let window = NSApp.keyWindow else { return false }
    return await withCheckedContinuation { continuation in
      let alert = makeAlert(for: backup)
      alert.beginSheetModal(for: window) { response in
        continuation.resume(returning: response == .alertSecondButtonReturn)
      }
    }
  }

  func makeAlert(for backup: ManagedBackup) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Restore this backup?"
    alert.informativeText =
      "Current notes will be replaced. An emergency backup and recovery report will be created first."
    let cancelButton = alert.addButton(withTitle: "Cancel")
    cancelButton.keyEquivalent = "\r"
    let restoreButton = alert.addButton(withTitle: "Restore")
    restoreButton.hasDestructiveAction = true
    return alert
  }
}
