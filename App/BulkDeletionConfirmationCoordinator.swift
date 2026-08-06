import AppKit
import ForNowCore

enum BulkDeletionOperationError: Error, LocalizedError {
  case inProgress

  var errorDescription: String? {
    "Another bulk deletion operation is still in progress."
  }
}

@MainActor
final class BulkDeletionConfirmationCoordinator {
  func requestConfirmation(for preview: BulkDeletionPreview) async -> Bool {
    guard let window = NSApp.keyWindow else { return false }
    return await withCheckedContinuation { continuation in
      let alert = makeAlert(for: preview)
      alert.beginSheetModal(for: window) { response in
        continuation.resume(returning: response == .alertSecondButtonReturn)
      }
    }
  }

  func makeAlert(for preview: BulkDeletionPreview) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Permanently delete \(preview.count) \(noteLabel(preview.count))?"
    alert.informativeText =
      "This action cannot be undone. A safety backup will be created before deletion."
    let cancelButton = alert.addButton(withTitle: "Cancel")
    cancelButton.keyEquivalent = "\r"
    let deleteButton = alert.addButton(withTitle: "Delete \(preview.count)")
    deleteButton.hasDestructiveAction = true
    return alert
  }

  private func noteLabel(_ count: Int) -> String {
    count == 1 ? "note" : "notes"
  }
}
