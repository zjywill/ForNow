import ForNowCore
import Foundation

public enum TimerCommandDiagnosticCode: String, Codable, Sendable, Equatable {
  case invalidSyntax = "timer-invalid-syntax"
  case invalidDuration = "timer-invalid-duration"
  case durationOutOfRange = "timer-duration-out-of-range"
  case emptyTitle = "timer-empty-title"
  case documentTooLarge = "timer-document-too-large"
}

public struct TimerCommandDiagnostic: Sendable, Equatable {
  public let code: TimerCommandDiagnosticCode
  public let sourceRange: NSRange
  public let message: String

  public init(code: TimerCommandDiagnosticCode, sourceRange: NSRange, message: String) {
    self.code = code
    self.sourceRange = sourceRange
    self.message = message
  }
}

public struct TimerCommandMatch: Sendable, Equatable {
  public let command: TimerCommand
  public let matchedAlias: String
  public let sourceRange: NSRange
  public let anchorUTF16Offset: Int
  public let showsTutorial: Bool

  public init(
    command: TimerCommand,
    matchedAlias: String,
    sourceRange: NSRange,
    anchorUTF16Offset: Int,
    showsTutorial: Bool
  ) {
    self.command = command
    self.matchedAlias = matchedAlias
    self.sourceRange = sourceRange
    self.anchorUTF16Offset = anchorUTF16Offset
    self.showsTutorial = showsTutorial
  }
}

public enum TimerCommandLineEvaluation: Sendable, Equatable {
  case command(TimerCommandMatch)
  case diagnostic(TimerCommandDiagnostic)
}

public struct TimerCommandDocument: Sendable, Equatable {
  public let commands: [TimerCommandMatch]
  public let diagnostics: [TimerCommandDiagnostic]

  public init(
    commands: [TimerCommandMatch] = [],
    diagnostics: [TimerCommandDiagnostic] = []
  ) {
    self.commands = commands
    self.diagnostics = diagnostics
  }
}

public struct TimerCommandParser: Sendable {
  public static let maximumLineCount = 10_000
  public static let maximumDurationSeconds = 7 * 24 * 60 * 60

  private enum DurationParseError: Error, Equatable {
    case invalid
    case outOfRange
  }

  private let registry: ModeAliasRegistry?

  public init(settings: ModeSettings = ModeSettings()) {
    registry = try? ModeAliasRegistry(settings: settings)
  }

  public init(registry: ModeAliasRegistry) {
    self.registry = registry
  }

  public func parse(in source: String) -> TimerCommandDocument {
    (try? parse(source, checksCancellation: false)) ?? TimerCommandDocument()
  }

  public func parseCancellable(in source: String) throws -> TimerCommandDocument {
    try parse(source, checksCancellation: true)
  }

  public func evaluateLine(
    _ line: String,
    sourceRange: NSRange? = nil,
    isFirstSourceLine: Bool = false
  ) -> TimerCommandLineEvaluation? {
    guard let registry, registry.keywordInterpretationEnabled,
      let firstScalar = line.unicodeScalars.first
    else { return nil }
    let lineRange = sourceRange ?? NSRange(location: 0, length: line.utf16.count)
    guard !CharacterSet.whitespacesAndNewlines.contains(firstScalar) else {
      return nil
    }
    let nsLine = line as NSString
    var tokenEnd = 0
    while tokenEnd < nsLine.length {
      let character = nsLine.character(at: tokenEnd)
      if character == 0x20 || character == 0x09 { break }
      tokenEnd += 1
    }
    let sourceAlias = nsLine.substring(with: NSRange(location: 0, length: tokenEnd))
    guard registry.modeID(matching: sourceAlias) == .timer else { return nil }
    let matchedAlias = ModeAliasRegistry.normalize(sourceAlias)
    let remainder = nsLine.substring(from: tokenEnd)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let showsTutorial = isFirstSourceLine && remainder.isEmpty

    do {
      let command = try command(from: remainder)
      return .command(
        TimerCommandMatch(
          command: command,
          matchedAlias: matchedAlias,
          sourceRange: lineRange,
          anchorUTF16Offset: NSMaxRange(lineRange),
          showsTutorial: showsTutorial
        )
      )
    } catch let error as DurationParseError {
      let code: TimerCommandDiagnosticCode =
        error == .outOfRange ? .durationOutOfRange : .invalidDuration
      let message =
        error == .outOfRange
        ? "Timer durations must be greater than zero and no longer than seven days."
        : "Use decimal minutes or m:ss for timer durations."
      return .diagnostic(
        TimerCommandDiagnostic(code: code, sourceRange: lineRange, message: message)
      )
    } catch let error as TimerCommandDiagnosticCode {
      let message: String
      switch error {
      case .emptyTitle:
        message = "A timer title cannot be empty."
      case .invalidSyntax:
        message = "This timer command is not supported."
      case .invalidDuration:
        message = "Use decimal minutes or m:ss for timer durations."
      case .durationOutOfRange:
        message = "Timer durations must be greater than zero and no longer than seven days."
      case .documentTooLarge:
        message = "Timer command parsing is limited to 10,000 lines."
      }
      return .diagnostic(
        TimerCommandDiagnostic(code: error, sourceRange: lineRange, message: message)
      )
    } catch {
      return .diagnostic(
        TimerCommandDiagnostic(
          code: .invalidSyntax,
          sourceRange: lineRange,
          message: "This timer command is not supported."
        )
      )
    }
  }

  private func parse(_ source: String, checksCancellation: Bool) throws -> TimerCommandDocument {
    guard let registry, registry.keywordInterpretationEnabled, !source.isEmpty else {
      return TimerCommandDocument()
    }
    let nsSource = source as NSString
    var commands: [TimerCommandMatch] = []
    var diagnostics: [TimerCommandDiagnostic] = []
    var location = 0
    var lineIndex = 0
    while location < nsSource.length {
      if lineIndex.isMultiple(of: 32), checksCancellation {
        try Task.checkCancellation()
      }
      guard lineIndex < Self.maximumLineCount else {
        diagnostics.append(
          TimerCommandDiagnostic(
            code: .documentTooLarge,
            sourceRange: NSRange(location: 0, length: min(nsSource.length, 1)),
            message: "Timer command parsing is limited to 10,000 lines."
          )
        )
        break
      }
      var lineStart = 0
      var lineEnd = 0
      var contentsEnd = 0
      nsSource.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      let range = NSRange(location: lineStart, length: contentsEnd - lineStart)
      let line = nsSource.substring(with: range)
      switch evaluateLine(line, sourceRange: range, isFirstSourceLine: lineIndex == 0) {
      case .command(let match):
        commands.append(match)
      case .diagnostic(let diagnostic):
        diagnostics.append(diagnostic)
      case nil:
        break
      }
      lineIndex += 1
      location = lineEnd
    }
    if checksCancellation {
      try Task.checkCancellation()
    }
    return TimerCommandDocument(commands: commands, diagnostics: diagnostics)
  }

  private func command(from remainder: String) throws -> TimerCommand {
    guard !remainder.isEmpty else { return .startStopwatch(title: nil) }
    switch ModeAliasRegistry.normalize(remainder) {
    case "p": return .pauseOrResume
    case "r": return .restart
    case "s", "0": return .stop
    case "pomo": return .startPomodoro(work: .seconds(25 * 60), rest: .seconds(5 * 60), title: nil)
    default: break
    }

    let nsRemainder = remainder as NSString
    for location in 0..<nsRemainder.length where nsRemainder.character(at: location) == 0x3A {
      guard location + 1 < nsRemainder.length else {
        let prefix = nsRemainder.substring(to: location)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if (try? startCommand(from: prefix, title: nil)) != nil {
          throw TimerCommandDiagnosticCode.emptyTitle
        }
        continue
      }
      let nextCharacter = nsRemainder.character(at: location + 1)
      guard nextCharacter == 0x20 || nextCharacter == 0x09 else { continue }
      let prefix = nsRemainder.substring(to: location)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let title = nsRemainder.substring(from: location + 1)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        if (try? startCommand(from: prefix, title: nil)) != nil {
          throw TimerCommandDiagnosticCode.emptyTitle
        }
        continue
      }
      return try startCommand(from: prefix, title: title)
    }
    return try startCommand(from: remainder, title: nil)
  }

  private func startCommand(from source: String, title: String?) throws -> TimerCommand {
    let tokens = source.split(whereSeparator: { $0 == " " || $0 == "\t" })
    switch tokens.count {
    case 1:
      return .startCountdown(duration: try duration(from: String(tokens[0])), title: title)
    case 2:
      return .startPomodoro(
        work: try duration(from: String(tokens[0])),
        rest: try duration(from: String(tokens[1])),
        title: title
      )
    default:
      throw TimerCommandDiagnosticCode.invalidSyntax
    }
  }

  private func duration(from token: String) throws -> Duration {
    let seconds: Double
    let colonParts = token.split(separator: ":", omittingEmptySubsequences: false)
    if colonParts.count == 2 {
      let minuteToken = colonParts[0]
      let secondToken = colonParts[1]
      guard !minuteToken.isEmpty,
        minuteToken.allSatisfy(\.isASCIIWholeNumber),
        secondToken.count == 2,
        secondToken.allSatisfy(\.isASCIIWholeNumber),
        let minutes = Double(minuteToken),
        let remainderSeconds = Double(secondToken),
        remainderSeconds < 60
      else {
        throw DurationParseError.invalid
      }
      seconds = minutes * 60 + remainderSeconds
    } else {
      guard colonParts.count == 1,
        token.unicodeScalars.allSatisfy({ (0x30...0x39).contains($0.value) || $0.value == 0x2E }),
        token.filter({ $0 == "." }).count <= 1,
        token.first != ".",
        token.last != ".",
        let minutes = Double(token),
        minutes.isFinite
      else {
        throw DurationParseError.invalid
      }
      seconds = minutes * 60
    }
    guard seconds > 0, seconds <= Double(Self.maximumDurationSeconds) else {
      throw DurationParseError.outOfRange
    }
    return TimerDuration.duration(seconds: seconds)
  }
}

extension TimerCommandDiagnosticCode: Error {}

extension Character {
  fileprivate var isASCIIWholeNumber: Bool {
    unicodeScalars.count == 1
      && unicodeScalars.first.map { (0x30...0x39).contains($0.value) } == true
  }
}
