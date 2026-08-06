import ForNowEditor
import SwiftUI

struct FindReplacePanel: View {
  let environment: AppEnvironment

  @ObservedObject private var model: FindReplaceModel

  init(environment: AppEnvironment) {
    self.environment = environment
    _model = ObservedObject(wrappedValue: environment.findReplace)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      findRow
      if model.isReplacementVisible {
        replacementRow
      }
      optionsRow
    }
    .padding(10)
    .frame(width: 500)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
    .padding(12)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Find and replace")
  }

  private var findRow: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .frame(width: 16)

      FindReplaceCommandField(
        text: model.query,
        role: .find,
        placeholder: "Find",
        accessibilityIdentifier: "Current note find field",
        focusRequest: model.findFocusRequest,
        textDidChange: { model.setQuery($0) },
        commandHandler: { handleCommand($0) }
      )
      .frame(height: 24)

      Text(model.statusText)
        .font(.caption.monospacedDigit())
        .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
        .frame(width: 92, alignment: .trailing)
        .lineLimit(1)

      Button {
        model.navigate(by: -1)
      } label: {
        Image(systemName: "chevron.up")
      }
      .buttonStyle(.borderless)
      .frame(width: 22, height: 22)
      .disabled(model.matches.isEmpty)
      .help("Previous Match")

      Button {
        model.navigate(by: 1)
      } label: {
        Image(systemName: "chevron.down")
      }
      .buttonStyle(.borderless)
      .frame(width: 22, height: 22)
      .disabled(model.matches.isEmpty)
      .help("Next Match")

      Button {
        model.toggleReplacementVisibility()
      } label: {
        Image(
          systemName: model.isReplacementVisible
            ? "chevron.up.chevron.down" : "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.borderless)
      .frame(width: 22, height: 22)
      .help(model.isReplacementVisible ? "Hide Replace" : "Show Replace")

      Button {
        environment.dismissFindReplace()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .frame(width: 22, height: 22)
      .help("Close")
    }
  }

  private var replacementRow: some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.right")
        .foregroundStyle(.secondary)
        .frame(width: 16)

      FindReplaceCommandField(
        text: model.replacement,
        role: .replacement,
        placeholder: "Replace with",
        accessibilityIdentifier: "Current note replacement field",
        focusRequest: model.replacementFocusRequest,
        textDidChange: { model.setReplacement($0) },
        commandHandler: { handleCommand($0) }
      )
      .frame(height: 24)

      Button("Replace") {
        _ = model.replaceCurrent()
      }
      .disabled(model.selectedMatch == nil || model.errorMessage != nil)

      Button("Replace All") {
        _ = model.replaceAll()
      }
      .disabled(model.matches.isEmpty || model.errorMessage != nil)
    }
  }

  private var optionsRow: some View {
    HStack(spacing: 10) {
      Picker(
        "Match mode",
        selection: Binding(
          get: { model.matchMode },
          set: { model.setMatchMode($0) }
        )
      ) {
        ForEach(FindMatchMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 150, alignment: .leading)

      Toggle(
        "Case sensitive",
        isOn: Binding(
          get: { model.isCaseSensitive },
          set: { model.setCaseSensitive($0) }
        )
      )
      .toggleStyle(.checkbox)
      .controlSize(.small)

      Spacer()
    }
  }

  private func handleCommand(_ command: FindReplaceFieldCommand) {
    switch command {
    case .nextMatch:
      model.navigate(by: 1)
    case .previousMatch:
      model.navigate(by: -1)
    case .showReplacement:
      model.showReplacement()
    case .replaceCurrent:
      _ = model.replaceCurrent()
    case .replaceAll:
      _ = model.replaceAll()
    case .dismiss:
      environment.dismissFindReplace()
    }
  }
}
