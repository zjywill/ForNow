import ForNowCore
import ForNowIntegrations
import SwiftUI

struct ExportSettingsSection: View {
  let environment: AppEnvironment

  @ObservedObject private var environmentModel: AppEnvironment
  @State private var draft: ExportSettings
  @State private var errorMessage: String?
  @State private var isSaving = false

  init(environment: AppEnvironment) {
    self.environment = environment
    _environmentModel = ObservedObject(wrappedValue: environment)
    _draft = State(initialValue: environment.exportSettings)
  }

  var body: some View {
    Section("Export") {
      Picker("Quick destination", selection: $draft.quickDestination) {
        ForEach(QuickExportDestination.allCases) { destination in
          Text(destination.displayName).tag(destination)
        }
      }
      Toggle("Omit mode keywords", isOn: $draft.omitsKeywords)
      Toggle("Use first line as title", isOn: $draft.usesFirstLineAsTitle)

      if draft.quickDestination == .obsidian {
        TextField("Obsidian vault (optional)", text: $draft.obsidianVault)
      }
      if draft.quickDestination == .appleNotes {
        TextField("Apple Shortcut name", text: $draft.appleShortcutName)
      }
      if draft.quickDestination == .customURL {
        TextField(
          "Custom URL template",
          text: $draft.customURLTemplate,
          axis: .vertical
        )
        .lineLimit(2...4)
      }

      HStack {
        Label(
          environmentModel.exportDestinationDiagnostic.message,
          systemImage: diagnosticSystemImage
        )
        .font(.caption)
        .foregroundStyle(diagnosticColor)
        .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button("Save Export Settings") {
          save()
        }
        .disabled(isSaving || validationErrorMessage != nil)
      }

      if let displayedError = errorMessage ?? validationErrorMessage {
        Text(displayedError)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onAppear {
      Task { await environment.refreshExportDestinationDiagnostic() }
    }
    .onChange(of: draft) { _, _ in
      errorMessage = nil
    }
    .onChange(of: environmentModel.exportSettings) { _, settings in
      guard !isSaving else { return }
      draft = settings
    }
  }

  private var validationErrorMessage: String? {
    guard draft.quickDestination == .customURL else { return nil }
    do {
      _ = try ValidatedCustomURLTemplate(source: draft.customURLTemplate)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  private var diagnosticSystemImage: String {
    switch environmentModel.exportDestinationDiagnostic.status {
    case .available: "checkmark.circle"
    case .requiresConfiguration: "exclamationmark.triangle"
    case .unavailable: "xmark.circle"
    }
  }

  private var diagnosticColor: Color {
    switch environmentModel.exportDestinationDiagnostic.status {
    case .available: .secondary
    case .requiresConfiguration, .unavailable: .red
    }
  }

  private func save() {
    guard !isSaving else { return }
    if let validationErrorMessage {
      errorMessage = validationErrorMessage
      return
    }
    isSaving = true
    errorMessage = nil
    let settings = draft
    Task {
      defer { isSaving = false }
      do {
        try await environment.updateExportSettings(settings)
        draft = environment.exportSettings
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
