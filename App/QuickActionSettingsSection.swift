import SwiftUI

struct QuickActionSettingsSection: View {
  let environment: AppEnvironment

  @ObservedObject private var environmentModel: AppEnvironment
  @State private var draft: QuickActionSettings
  @State private var errorMessage: String?
  @State private var isSaving = false

  init(environment: AppEnvironment) {
    self.environment = environment
    _environmentModel = ObservedObject(wrappedValue: environment)
    _draft = State(initialValue: environment.quickActionSettings)
  }

  var body: some View {
    Section("Shortcuts") {
      ForEach(QuickAction.allCases) { action in
        LabeledContent(action.displayName) {
          HStack(spacing: 8) {
            modifierMenu(for: action)
            TextField("Key", text: keyBinding(for: action))
              .multilineTextAlignment(.center)
              .frame(width: 44)
              .accessibilityLabel("\(action.displayName) key")
          }
        }
      }

      HStack {
        Button("Restore Defaults") {
          draft = QuickActionSettings()
          save()
        }
        Spacer()
        Button("Save Shortcuts") {
          save()
        }
        .disabled(isSaving)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("Shortcut settings error: \(errorMessage)")
      }
    }
    .onChange(of: environmentModel.quickActionSettings) { _, settings in
      guard !isSaving else { return }
      draft = settings
    }
  }

  private func modifierMenu(for action: QuickAction) -> some View {
    Menu {
      Toggle("Command", isOn: modifierBinding(.command, for: action))
      Toggle("Control", isOn: modifierBinding(.control, for: action))
      Toggle("Option", isOn: modifierBinding(.option, for: action))
      Toggle("Shift", isOn: modifierBinding(.shift, for: action))
    } label: {
      Text(
        draft[action].modifiers.displayName.isEmpty ? "None" : draft[action].modifiers.displayName
      )
      .frame(minWidth: 52)
    }
    .accessibilityLabel("\(action.displayName) modifiers")
  }

  private func keyBinding(for action: QuickAction) -> Binding<String> {
    Binding(
      get: { draft[action].key },
      set: { draft[action].key = String($0.prefix(1)) }
    )
  }

  private func modifierBinding(
    _ modifier: ShortcutModifiers,
    for action: QuickAction
  ) -> Binding<Bool> {
    Binding(
      get: { draft[action].modifiers.contains(modifier) },
      set: { isEnabled in
        if isEnabled {
          draft[action].modifiers.insert(modifier)
        } else {
          draft[action].modifiers.remove(modifier)
        }
      }
    )
  }

  private func save() {
    guard !isSaving else { return }
    isSaving = true
    errorMessage = nil
    let settings = draft
    Task {
      defer { isSaving = false }
      do {
        try await environment.updateQuickActionSettings(settings)
        draft = settings
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
