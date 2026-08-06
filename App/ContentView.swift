import AppKit
import ForNowDesign
import ForNowEditor
import ForNowWindowing
import SwiftUI

struct ContentView: View {
  let environment: AppEnvironment

  @ObservedObject private var noteSession: NoteSessionModel
  @ObservedObject private var noteSearch: NoteSearchModel
  @ObservedObject private var findReplace: FindReplaceModel
  @ObservedObject private var slashCommand: SlashCommandModel
  @ObservedObject private var environmentModel: AppEnvironment
  @ObservedObject private var timerModel: TimerModel
  @ObservedObject private var ocrModel: OCRWorkflowModel
  @ObservedObject private var autoPasteModel: AutoPasteModel

  init(environment: AppEnvironment) {
    self.environment = environment
    _noteSession = ObservedObject(wrappedValue: environment.noteSession)
    _noteSearch = ObservedObject(wrappedValue: environment.noteSearch)
    _findReplace = ObservedObject(wrappedValue: environment.findReplace)
    _slashCommand = ObservedObject(wrappedValue: environment.slashCommand)
    _environmentModel = ObservedObject(wrappedValue: environment)
    _timerModel = ObservedObject(wrappedValue: environment.timerModel)
    _ocrModel = ObservedObject(wrappedValue: environment.ocrModel)
    _autoPasteModel = ObservedObject(wrappedValue: environment.autoPasteModel)
  }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        if environmentModel.windowConfiguration.presence == .neither {
          NeitherPresenceToolbar(environment: environment)
        }

        ProjectionEditorView(
          sourceText: noteSession.text,
          accessibilityLabel: "Scratchpad",
          viewportState: EditorViewportState(
            selectionRange: noteSession.editorSelectionRange,
            scrollOffset: noteSession.editorScrollOffset
          ),
          viewportRestorationToken: noteSession.viewportRestorationToken,
          navigationEntryToken: noteSession.navigationEntryToken,
          pasteSettings: environmentModel.pasteSettings,
          editorSettings: environmentModel.editorSettings,
          appearanceSettings: environmentModel.appearanceSettings,
          modeSettings: environmentModel.modeSettings,
          mathSettings: environmentModel.mathSettings,
          currencyContext: environmentModel.currencyConversionContext,
          timerSnapshot: timerModel.snapshot(linkedTo: noteSession.currentNoteID),
          stopsTimerOnEscape: timerModel.snapshot?.isRunning == true,
          autoPasteIsActive: autoPasteModel.isActive,
          expandedLinkIdentities: environmentModel.expandedLinkIdentities(
            for: noteSession.currentNoteID
          ),
          findReplaceTarget: findReplace.editorTarget,
          slashCommandTarget: slashCommand.editorTarget,
          ocrTarget: ocrModel.editorTarget,
          sourceDidChange: { source, hasMarkedText in
            noteSession.editorTextChanged(source, hasMarkedText: hasMarkedText)
          },
          viewportDidChange: { viewport in
            noteSession.editorViewportChanged(
              selectionRange: viewport.selection.range.nsRange,
              scrollOffset: viewport.verticalScrollOffset
            )
          },
          navigationHandler: { direction in
            Task {
              try? await noteSession.navigate(direction)
            }
          },
          linkExpansionDidToggle: { identity in
            guard let noteID = noteSession.currentNoteID else { return }
            Task {
              try? await environment.toggleExpandedLink(identity, noteID: noteID)
            }
          },
          timerCommandDidCommit: { command, source in
            Task {
              try? await environment.executeTimerCommand(command, source: source)
            }
          },
          timerInteractionHandler: { interaction in
            Task {
              switch interaction {
              case .singleClick:
                try? await timerModel.handleSingleClick()
              case .stop:
                try? await timerModel.handleStop()
              }
            }
          },
          autoPasteCommandDidCommit: { command, source in
            Task {
              try? await environment.executeAutoPasteCommand(command, source: source)
            }
          },
          autoPasteStopHandler: {
            environment.stopAutoPaste(.escape)
          },
          pasteboardDidWrite: {
            environment.markCurrentClipboardChangeAsOwn()
          }
        )
        .overlay(alignment: .bottomTrailing) {
          if let noteCount = noteSession.visibleNoteCount {
            Text(noteCount, format: .number)
              .font(.caption.monospacedDigit())
              .foregroundStyle(
                Color(
                  nsColor: activeTheme.secondaryText.nsColor
                )
              )
              .padding(12)
              .accessibilityLabel("\(noteCount) notes")
          }
        }

        if let session = autoPasteModel.session, autoPasteModel.isActive {
          AutoPasteIndicator(session: session) {
            environment.stopAutoPaste(.indicator)
          }
        }
      }
      .allowsHitTesting(!noteSearch.isPresented)
      .accessibilityHidden(noteSearch.isPresented)

      if noteSearch.isPresented {
        NoteSearchOverlay(environment: environment)
      }

      if findReplace.isPresented {
        VStack {
          HStack {
            Spacer()
            FindReplacePanel(environment: environment)
          }
          Spacer()
        }
      }

      if slashCommand.isPresented {
        VStack {
          HStack {
            SlashCommandPanel(environment: environment)
            Spacer()
          }
          Spacer()
        }
        .padding(
          .top,
          environmentModel.windowConfiguration.presence == .neither ? 48 : 12
        )
        .padding(.leading, 12)
      }

      if ocrModel.isRecognizing {
        VStack(spacing: 0) {
          Spacer()
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Recognizing text")
              .font(.callout)
            Spacer()
            Button {
              ocrModel.cancel()
            } label: {
              Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .help("Cancel text recognition")
          }
          .padding(.horizontal, 12)
          .frame(height: 40)
          .background(Color(nsColor: .windowBackgroundColor))
          .overlay(alignment: .top) { Divider() }
        }
      }
    }
    .alert("Text changed during recognition", isPresented: staleInsertionBinding) {
      Button("Cancel", role: .cancel) {
        ocrModel.declineStaleInsertion()
      }
      Button("Insert at Current Cursor") {
        ocrModel.confirmInsertionAtCurrentSelection()
      }
    } message: {
      Text("The original insertion point is no longer current.")
    }
    .alert("Text Recognition Failed", isPresented: errorBinding) {
      Button("OK") {
        ocrModel.dismissError()
      }
    } message: {
      Text(ocrModel.errorMessage ?? "Text recognition failed.")
    }
    .alert("AutoPaste Stopped", isPresented: autoPasteErrorBinding) {
      Button("OK") {
        autoPasteModel.dismissError()
      }
    } message: {
      Text(autoPasteModel.errorMessage ?? "The destination could not be updated.")
    }
  }

  private var activeTheme: SemanticTheme {
    let appearance: InterfaceAppearance =
      NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? .dark : .light
    return environmentModel.appearanceSettings.theme(for: appearance)
  }

  private var staleInsertionBinding: Binding<Bool> {
    Binding(
      get: { ocrModel.requiresInsertionConfirmation },
      set: { isPresented in
        if !isPresented {
          ocrModel.declineStaleInsertion()
        }
      }
    )
  }

  private var errorBinding: Binding<Bool> {
    Binding(
      get: { ocrModel.errorMessage != nil },
      set: { isPresented in
        if !isPresented {
          ocrModel.dismissError()
        }
      }
    )
  }

  private var autoPasteErrorBinding: Binding<Bool> {
    Binding(
      get: { autoPasteModel.errorMessage != nil },
      set: { isPresented in
        if !isPresented {
          autoPasteModel.dismissError()
        }
      }
    )
  }
}

struct AutoPasteIndicator: View {
  let session: AutoPasteSession
  let stop: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reducesMotion
  @State private var dimsIcon = false

  var body: some View {
    HStack(spacing: 8) {
      AccessibleIconButton(
        systemName: "clipboard.fill",
        accessibilityLabel: "Stop AutoPaste",
        tintColor: .controlAccentColor,
        action: stop
      )
      .frame(width: 28, height: 28)
      .opacity(reducesMotion || !dimsIcon ? 1 : 0.35)

      Text("AutoPaste to \(session.destinationName)")
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 8)

      if session.captureCount > 0 {
        Text(session.captureCount, format: .number)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel("\(session.captureCount) captured items")
      }

      AccessibleIconButton(
        systemName: "xmark",
        accessibilityLabel: "Stop AutoPaste",
        tintColor: .secondaryLabelColor,
        action: stop
      )
      .frame(width: 28, height: 28)
    }
    .padding(.horizontal, 10)
    .frame(height: 40)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .top) { Divider() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("AutoPaste status")
    .accessibilityLabel("AutoPaste active for \(session.destinationName)")
    .onAppear { updateAnimation() }
    .onChange(of: reducesMotion) { _, _ in updateAnimation() }
  }

  private func updateAnimation() {
    if reducesMotion {
      dimsIcon = false
    } else {
      withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
        dimsIcon = true
      }
    }
  }
}

@MainActor
private struct AccessibleIconButton: NSViewRepresentable {
  let systemName: String
  let accessibilityLabel: String
  let tintColor: NSColor
  let action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton()
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.setButtonType(.momentaryPushIn)
    button.target = context.coordinator
    button.action = #selector(Coordinator.activate)
    configure(button)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.action = action
    configure(button)
  }

  private func configure(_ button: NSButton) {
    button.image = NSImage(
      systemSymbolName: systemName,
      accessibilityDescription: accessibilityLabel
    )
    button.contentTintColor = tintColor
    button.toolTip = accessibilityLabel
    button.setAccessibilityLabel(accessibilityLabel)
    button.setAccessibilityIdentifier(accessibilityLabel)
  }

  @MainActor
  final class Coordinator: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc func activate() {
      action()
    }
  }
}

private struct NeitherPresenceToolbar: View {
  let environment: AppEnvironment

  var body: some View {
    HStack(spacing: 8) {
      Menu {
        Button("Previous Note") {
          Task { try? await environment.noteSession.navigate(.previous) }
        }
        Button("Next Note") {
          Task { try? await environment.noteSession.navigate(.next) }
        }
        Button("Newest Note") {
          Task { try? await environment.noteSession.jumpToNewest() }
        }
        Button("Promote Note") {
          Task { try? await environment.noteSession.promoteCurrent() }
        }
        Button("Search Notes") {
          environment.openSearch()
        }
        Button("Delete Note") {
          Task { try? await environment.deleteCurrentNote() }
        }
        Divider()
        Button("Toggle Window") {
          environment.toggleWindow()
        }
        Button(environment.windowConfiguration.isPinned ? "Unpin Window" : "Pin Window") {
          Task { try? await environment.togglePin() }
        }
        SettingsLink {
          Text("Settings")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .frame(width: 28)
      .help("Commands")

      Spacer()

      Button {
        Task { try? await environment.togglePin() }
      } label: {
        Image(systemName: environment.windowConfiguration.isPinned ? "pin.fill" : "pin")
      }
      .buttonStyle(.borderless)
      .frame(width: 28, height: 28)
      .help(environment.windowConfiguration.isPinned ? "Unpin Window" : "Pin Window")

      Button {
        environment.closeWindow()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .frame(width: 28, height: 28)
      .help("Close Window")
    }
    .controlSize(.small)
    .padding(.horizontal, 10)
    .frame(height: 36)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .bottom) { Divider() }
  }
}

#Preview {
  ContentView(environment: .preview())
    .frame(width: 620, height: 540)
}
