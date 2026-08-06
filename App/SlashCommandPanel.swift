import ForNowModes
import SwiftUI

struct SlashCommandPanel: View {
  let environment: AppEnvironment

  @ObservedObject private var model: SlashCommandModel

  init(environment: AppEnvironment) {
    self.environment = environment
    _model = ObservedObject(wrappedValue: environment.slashCommand)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Image(systemName: "line.3.horizontal.decrease")
          .foregroundStyle(.secondary)
        Text(model.query.isEmpty ? "/" : "/\(model.query)")
          .font(.callout.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
      }
      .padding(.horizontal, 8)
      .frame(height: 26)
      .accessibilityLabel("Command filter")
      .accessibilityValue(model.query)

      Divider()

      if model.commands.isEmpty {
        Text("No commands")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(10)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(Array(model.commands.enumerated()), id: \.element.modeID) { index, command in
                Button {
                  _ = model.selectVisibleCommand(at: index)
                } label: {
                  HStack(spacing: 10) {
                    Text("\(index + 1)")
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(.secondary)
                      .frame(width: 14, alignment: .trailing)

                    Image(systemName: symbol(for: command.modeID))
                      .frame(width: 18)
                      .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 1) {
                      Text(command.modeID.displayName)
                        .font(.callout.weight(.medium))
                      Text(command.mainAlias)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if model.selectedIndex == index {
                      Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                  .padding(.horizontal, 8)
                  .frame(height: 32)
                  .contentShape(Rectangle())
                  .background(
                    model.selectedIndex == index
                      ? Color.accentColor.opacity(0.14) : Color.clear
                  )
                  .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .id(command.modeID)
                .accessibilityLabel("\(command.modeID.displayName), \(command.mainAlias)")
                .accessibilityValue(
                  model.selectedIndex == index
                    ? "Selected, \(index + 1) of \(model.commands.count)"
                    : "\(index + 1) of \(model.commands.count)"
                )
                .accessibilityAddTraits(model.selectedIndex == index ? .isSelected : [])
              }
            }
          }
          .scrollIndicators(.visible)
          .frame(height: min(CGFloat(model.commands.count) * 34, 204))
          .onChange(of: model.selectedIndex) { _, selectedIndex in
            guard let selectedIndex, model.commands.indices.contains(selectedIndex) else { return }
            proxy.scrollTo(model.commands[selectedIndex].modeID, anchor: .center)
          }
        }
      }
    }
    .padding(6)
    .frame(width: 300)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Slash command menu")
    .accessibilityIdentifier("Slash command menu")
  }

  private func symbol(for modeID: ModeID) -> String {
    switch modeID {
    case .plain:
      "doc.plaintext"
    case .list:
      "checklist"
    case .math:
      "function"
    case .sum:
      "sum"
    case .average:
      "divide"
    case .count:
      "number"
    case .code:
      "chevron.left.forwardslash.chevron.right"
    case .timer:
      "timer"
    }
  }
}
