import ForNowModes
import Foundation

public protocol ProjectionParsing: Sendable {
  func parse(_ snapshot: SourceSnapshot) async throws -> EditorProjection
}

public struct ProductionProjectionParser: ProjectionParsing, Sendable {
  private let parser: SpikeProjectionParser

  public init(
    parser: SpikeProjectionParser = SpikeProjectionParser()
  ) {
    self.parser = parser
  }

  public init(editorSettings: EditorSettings) {
    parser = SpikeProjectionParser(editorSettings: editorSettings)
  }

  public init(editorSettings: EditorSettings, modeSettings: ModeSettings) {
    parser = SpikeProjectionParser(
      editorSettings: editorSettings,
      modeSettings: modeSettings
    )
  }

  public func parse(_ snapshot: SourceSnapshot) async throws -> EditorProjection {
    let parser = self.parser
    let parseTask = Task.detached(priority: .userInitiated) {
      try parser.parseCancellable(snapshot)
    }
    return try await withTaskCancellationHandler(
      operation: {
        try await parseTask.value
      },
      onCancel: {
        parseTask.cancel()
      }
    )
  }
}

public enum ProjectionPipelineError: Error, Equatable {
  case sourceVersionMismatch(expected: UInt64, actual: UInt64)
}

public struct ProjectionPipelineDiagnostics: Sendable, Equatable {
  public let submittedCount: UInt64
  public let completedCount: UInt64
  public let cancelledCount: UInt64
  public let staleResultCount: UInt64
  public let rejectedVersionCount: UInt64
  public let latestRequestedVersion: UInt64?
  public let latestAppliedVersion: UInt64?
  public let latestDuration: Duration?
  public let latestDecorationCount: Int
  public let latestDiagnosticCount: Int

  public init(
    submittedCount: UInt64 = 0,
    completedCount: UInt64 = 0,
    cancelledCount: UInt64 = 0,
    staleResultCount: UInt64 = 0,
    rejectedVersionCount: UInt64 = 0,
    latestRequestedVersion: UInt64? = nil,
    latestAppliedVersion: UInt64? = nil,
    latestDuration: Duration? = nil,
    latestDecorationCount: Int = 0,
    latestDiagnosticCount: Int = 0
  ) {
    self.submittedCount = submittedCount
    self.completedCount = completedCount
    self.cancelledCount = cancelledCount
    self.staleResultCount = staleResultCount
    self.rejectedVersionCount = rejectedVersionCount
    self.latestRequestedVersion = latestRequestedVersion
    self.latestAppliedVersion = latestAppliedVersion
    self.latestDuration = latestDuration
    self.latestDecorationCount = latestDecorationCount
    self.latestDiagnosticCount = latestDiagnosticCount
  }
}

public struct EditorProjectionValidator: Sendable {
  public init() {}

  public func validate(
    _ projection: EditorProjection,
    for snapshot: SourceSnapshot
  ) -> EditorProjection {
    var diagnostics = projection.diagnostics.filter { diagnostic in
      guard let range = diagnostic.sourceRange else { return true }
      return snapshot.contains(range)
    }
    let validDecorations = projection.decorations.filter { decoration in
      let isValid: Bool
      switch decoration {
      case .style(let range, _), .link(let range, _):
        isValid = snapshot.contains(range)
      case .checkbox(let range, let markerRange, _):
        isValid =
          snapshot.contains(range)
          && markerRange.map(snapshot.contains) != false
      case .result(let anchor, _):
        isValid = anchor.utf16Offset <= snapshot.utf16Count
      }
      if !isValid {
        diagnostics.append(
          ProjectionDiagnostic(
            code: "invalid-decoration-range",
            severity: .error,
            message: "A projection decoration was discarded because its source range is invalid."
          )
        )
      }
      return isValid
    }
    return EditorProjection(
      sourceVersion: projection.sourceVersion,
      decorations: validDecorations,
      diagnostics: diagnostics
    )
  }
}

public actor ProjectionParsePipeline {
  private struct ActiveRequest {
    let id: UInt64
    let task: Task<EditorProjection, any Error>
  }

  private let parser: any ProjectionParsing
  private let validator: EditorProjectionValidator
  private let clock = ContinuousClock()
  private var nextRequestID: UInt64 = 0
  private var activeRequest: ActiveRequest?
  private var submittedCount: UInt64 = 0
  private var completedCount: UInt64 = 0
  private var cancelledCount: UInt64 = 0
  private var staleResultCount: UInt64 = 0
  private var rejectedVersionCount: UInt64 = 0
  private var latestRequestedVersion: UInt64?
  private var latestAppliedVersion: UInt64?
  private var latestDuration: Duration?
  private var latestDecorationCount = 0
  private var latestDiagnosticCount = 0

  public init(
    parser: any ProjectionParsing = ProductionProjectionParser(),
    validator: EditorProjectionValidator = EditorProjectionValidator()
  ) {
    self.parser = parser
    self.validator = validator
  }

  public func projection(for snapshot: SourceSnapshot) async throws -> EditorProjection {
    nextRequestID &+= 1
    let requestID = nextRequestID
    submittedCount &+= 1
    latestRequestedVersion = snapshot.version
    activeRequest?.task.cancel()

    let parser = self.parser
    let task = Task {
      try await parser.parse(snapshot)
    }
    activeRequest = ActiveRequest(id: requestID, task: task)
    let startedAt = clock.now

    do {
      let unvalidated = try await withTaskCancellationHandler(
        operation: {
          try await task.value
        },
        onCancel: {
          task.cancel()
        }
      )
      try Task.checkCancellation()
      guard requestID == activeRequest?.id else {
        staleResultCount &+= 1
        throw CancellationError()
      }
      guard unvalidated.sourceVersion == snapshot.version else {
        rejectedVersionCount &+= 1
        activeRequest = nil
        throw ProjectionPipelineError.sourceVersionMismatch(
          expected: snapshot.version,
          actual: unvalidated.sourceVersion
        )
      }

      let projection = validator.validate(unvalidated, for: snapshot)
      completedCount &+= 1
      latestAppliedVersion = projection.sourceVersion
      latestDuration = startedAt.duration(to: clock.now)
      latestDecorationCount = projection.decorations.count
      latestDiagnosticCount = projection.diagnostics.count
      activeRequest = nil
      return projection
    } catch {
      if error is CancellationError {
        cancelledCount &+= 1
      }
      if requestID == activeRequest?.id {
        activeRequest = nil
      }
      throw error
    }
  }

  public func cancel() {
    nextRequestID &+= 1
    activeRequest?.task.cancel()
    activeRequest = nil
  }

  public func diagnostics() -> ProjectionPipelineDiagnostics {
    ProjectionPipelineDiagnostics(
      submittedCount: submittedCount,
      completedCount: completedCount,
      cancelledCount: cancelledCount,
      staleResultCount: staleResultCount,
      rejectedVersionCount: rejectedVersionCount,
      latestRequestedVersion: latestRequestedVersion,
      latestAppliedVersion: latestAppliedVersion,
      latestDuration: latestDuration,
      latestDecorationCount: latestDecorationCount,
      latestDiagnosticCount: latestDiagnosticCount
    )
  }
}
