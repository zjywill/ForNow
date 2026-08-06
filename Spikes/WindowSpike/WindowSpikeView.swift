import ForNowWindowing
import SwiftUI

struct WindowSpikeView: View {
  @ObservedObject var model: WindowSpikeModel
  @FocusState private var editorFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: headerSpacing) {
        Picker(
          "Mode",
          selection: Binding(
            get: { model.configuration.mode },
            set: { model.setMode($0) }
          )
        ) {
          Text("Standard").tag(WindowPresentationMode.standard)
          Text("Floating").tag(WindowPresentationMode.menuBarPanel)
          Text("Dropdown").tag(WindowPresentationMode.dropdownPanel)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minWidth: 190, idealWidth: 270, maxWidth: 270)

        Menu {
          ForEach(ApplicationPresenceMode.allCases, id: \.self) { presence in
            Button(presenceLabel(presence)) {
              model.setPresence(presence)
            }
          }
        } label: {
          Image(systemName: "menubar.rectangle")
        }
        .frame(width: 30)
        .accessibilityLabel("Application presence: \(presenceLabel(model.configuration.presence))")
        .help("Application presence")

        Spacer(minLength: 8)

        Toggle(
          isOn: Binding(
            get: { model.configuration.isPinned },
            set: { model.setPinned($0) }
          )
        ) {
          Image(systemName: model.configuration.isPinned ? "pin.fill" : "pin")
        }
        .toggleStyle(.button)
        .frame(width: 30)
        .accessibilityLabel("Pin")
        .help("Keep above ordinary windows")

        Toggle(
          isOn: Binding(
            get: { model.configuration.autoHideEnabled },
            set: { model.setAutoHide($0) }
          )
        ) {
          Image(systemName: "eye.slash")
        }
        .toggleStyle(.button)
        .frame(width: 30)
        .accessibilityLabel("Auto-hide")
        .help("Hide after focus leaves the app")
      }
      .controlSize(.small)
      .padding(.horizontal, horizontalPadding)
      .frame(height: 48)

      Divider()

      TextEditor(text: $model.draft)
        .font(.system(size: 18, weight: .regular, design: .default))
        .scrollContentBackground(.hidden)
        .padding(18)
        .background(Color(nsColor: .textBackgroundColor))
        .focused($editorFocused)
        .accessibilityLabel("Window spike editor")
        .accessibilityIdentifier("WindowSpikeEditor")

      Divider()

      VStack(spacing: 10) {
        if model.configuration.mode == .dropdownPanel {
          HStack(spacing: 12) {
            Stepper(
              "Width \(Int(model.configuration.dropdownDimensions.width))",
              value: Binding<Double>(
                get: { Double(model.configuration.dropdownDimensions.width) },
                set: { model.setDropdownWidth(CGFloat($0)) }
              ),
              in: 360...1_200,
              step: 20
            )
            Stepper(
              "Height \(Int(model.configuration.dropdownDimensions.height))",
              value: Binding<Double>(
                get: { Double(model.configuration.dropdownDimensions.height) },
                set: { model.setDropdownHeight(CGFloat($0)) }
              ),
              in: 280...1_000,
              step: 20
            )
            Spacer()
          }
          .controlSize(.small)
        }

        HStack(spacing: 8) {
          ShortcutRecorder(
            candidate: model.shortcut,
            onCandidate: { model.applyShortcut($0) },
            onResult: { result in
              model.appendLog("shortcut \(result.message)")
            }
          )
          .frame(width: 120)

          Button {
            model.coordinator?.showSettingsPanel()
          } label: {
            Image(systemName: "gearshape")
          }
          .frame(width: 30)
          .accessibilityLabel("Settings")
          .help("Open settings panel")

          Button {
            model.coordinator?.showSavePanel()
          } label: {
            Image(systemName: "square.and.arrow.down")
          }
          .frame(width: 30)
          .accessibilityLabel("Save")
          .help("Open save panel")

          Button {
            model.coordinator?.showPermissionPanel()
          } label: {
            Image(systemName: "lock.shield")
          }
          .frame(width: 30)
          .accessibilityLabel("Permission")
          .help("Open permission panel")

          Button {
            model.coordinator?.toggleWindowCommand()
          } label: {
            Image(systemName: "rectangle.compress.vertical")
          }
          .frame(width: 30)
          .accessibilityLabel("Toggle window")
          .help("Toggle window")

          Button {
            model.coordinator?.closeWindowCommand()
          } label: {
            Image(systemName: "xmark")
          }
          .frame(width: 30)
          .accessibilityLabel("Close window")
          .help("Close window")

          Spacer(minLength: 0)
        }
        .controlSize(.small)

        HStack(spacing: 8) {
          Text(model.status)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Window transition status")

          Text("Flushes \(model.flushCount)")
            .monospacedDigit()
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, 12)
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(minWidth: minimumContentWidth, minHeight: minimumContentHeight)
    .task {
      editorFocused = true
    }
    .onChange(of: model.focusGeneration) {
      editorFocused = true
    }
  }

  private var minimumContentWidth: CGFloat {
    model.configuration.mode == .dropdownPanel ? DropdownDimensions.minimum.width : 620
  }

  private var minimumContentHeight: CGFloat? {
    model.configuration.mode == .dropdownPanel ? nil : 440
  }

  private var horizontalPadding: CGFloat {
    model.configuration.mode == .dropdownPanel ? 8 : 16
  }

  private var headerSpacing: CGFloat {
    model.configuration.mode == .dropdownPanel ? 6 : 12
  }

  private func presenceLabel(_ presence: ApplicationPresenceMode) -> String {
    switch presence {
    case .dock: "Dock"
    case .menuBar: "Menu Bar"
    case .both: "Both"
    case .neither: "Neither"
    }
  }
}

private struct ShortcutRecorder: NSViewRepresentable {
  let candidate: GlobalShortcutCandidate
  let onCandidate: (GlobalShortcutCandidate) -> ShortcutRegistrationResult
  let onResult: (ShortcutRegistrationResult) -> Void

  func makeNSView(context: Context) -> ValidatedShortcutRecorderCocoa {
    let recorder = ValidatedShortcutRecorderCocoa(currentCandidate: candidate)
    recorder.candidateHandler = onCandidate
    recorder.resultHandler = onResult
    return recorder
  }

  func updateNSView(_ nsView: ValidatedShortcutRecorderCocoa, context: Context) {
    if nsView.currentCandidate != candidate {
      nsView.currentCandidate = candidate
    }
  }
}
