import AppKit

struct DeleteConfirmationResult: Equatable, Sendable {
  let confirmsDeletion: Bool
  let suppressesFutureWarning: Bool
}

@MainActor
final class DeleteConfirmationCoordinator {
  func requestConfirmation() async -> DeleteConfirmationResult {
    guard let window = NSApp.keyWindow else {
      return DeleteConfirmationResult(
        confirmsDeletion: false,
        suppressesFutureWarning: false
      )
    }

    return await withCheckedContinuation { continuation in
      let alert = makeAlert()
      alert.beginSheetModal(for: window) { response in
        continuation.resume(
          returning: DeleteConfirmationResult(
            confirmsDeletion: response == .alertSecondButtonReturn,
            suppressesFutureWarning: alert.suppressionButton?.state == .on
          )
        )
      }
    }
  }

  func makeAlert() -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Delete this note?"
    alert.informativeText = "This permanently deletes the note. Recovery requires a backup."
    let cancelButton = alert.addButton(withTitle: "Cancel")
    cancelButton.keyEquivalent = "\r"
    let deleteButton = alert.addButton(withTitle: "Delete")
    deleteButton.hasDestructiveAction = true
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Do not ask again"
    return alert
  }
}
