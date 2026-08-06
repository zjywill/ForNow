import SwiftUI

struct NoteSearchOverlay: View {
  let environment: AppEnvironment

  @ObservedObject private var model: NoteSearchModel

  init(environment: AppEnvironment) {
    self.environment = environment
    _model = ObservedObject(wrappedValue: environment.noteSearch)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .top) {
        Color.black.opacity(0.16)
          .contentShape(Rectangle())
          .onTapGesture { environment.dismissSearch() }

        VStack(spacing: 0) {
          NoteSearchCommandField(
            text: model.query,
            focusRequest: model.focusRequest,
            textDidChange: model.setQuery,
            commandHandler: handleCommand
          )
          .frame(height: 28)
          .padding(10)

          Divider()

          resultContent
            .frame(height: resultHeight(for: geometry.size.height))
        }
        .frame(width: panelWidth(for: geometry.size.width))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(.top, 12)
      }
    }
  }

  @ViewBuilder
  private var resultContent: some View {
    if let errorMessage = model.errorMessage {
      Text(errorMessage)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(errorMessage)
    } else if model.results.isEmpty {
      Text(model.isSearching ? "Searching..." : "No notes found")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.results) { result in
              resultRow(result)
                .id(result.id)
                .onAppear { model.loadNextPageIfNeeded(after: result.id) }
            }

            if model.isSearching {
              ProgressView()
                .controlSize(.small)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
            }
          }
        }
        .onChange(of: model.selectedIndex) { _, index in
          guard model.results.indices.contains(index) else { return }
          proxy.scrollTo(model.results[index].id, anchor: .center)
        }
      }
    }
  }

  private func resultRow(_ result: NoteSearchResultPresentation) -> some View {
    let isSelected = model.selectedResult?.id == result.id
    return ZStack {
      NoteSearchAccessibilityView(
        label: result.accessibilityDescription,
        isSelected: isSelected,
        activationHandler: { activate(result) }
      )

      Button {
        activate(result)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            Text(result.title)
              .font(.body.weight(.medium))
              .lineLimit(1)
            Text(result.context)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Text(result.modifiedAt, format: .dateTime.month(.abbreviated).day())
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHidden(true)
    }
  }

  private func activate(_ result: NoteSearchResultPresentation) {
    model.selectResult(id: result.id)
    Task { await environment.activateSelectedSearchResult() }
  }

  private func handleCommand(_ command: NoteSearchFieldCommand) {
    switch command {
    case .moveUp:
      model.moveSelection(by: -1)
    case .moveDown:
      model.moveSelection(by: 1)
    case .activate:
      Task { await environment.activateSelectedSearchResult() }
    case .dismiss:
      environment.dismissSearch()
    }
  }

  private func panelWidth(for availableWidth: CGFloat) -> CGFloat {
    min(max(availableWidth - 32, 280), 560)
  }

  private func resultHeight(for availableHeight: CGFloat) -> CGFloat {
    min(max(availableHeight - 100, 130), 360)
  }
}
