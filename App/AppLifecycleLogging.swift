import Foundation
import OSLog

enum AppLifecycleService: String, Equatable, Sendable {
  case repository
  case clipboard
  case notifications
  case windowCoordinator
}

enum AppLifecycleEvent: Equatable, Sendable {
  case startupBegan
  case serviceStarted(AppLifecycleService)
  case noteSessionLoaded
  case startupCompleted
  case startupFailed
  case shutdownBegan
  case noteSessionPrepared
  case noteSessionPreparationFailed
  case repositoryFlushed
  case repositoryFlushFailed
  case repositoryFlushSkipped
  case serviceStopped(AppLifecycleService)
  case repositoryShutdownFailed
  case shutdownCompleted
  case shutdownFailed

  var name: String {
    switch self {
    case .startupBegan: "startup_began"
    case .serviceStarted: "service_started"
    case .noteSessionLoaded: "note_session_loaded"
    case .startupCompleted: "startup_completed"
    case .startupFailed: "startup_failed"
    case .shutdownBegan: "shutdown_began"
    case .noteSessionPrepared: "note_session_prepared"
    case .noteSessionPreparationFailed: "note_session_preparation_failed"
    case .repositoryFlushed: "repository_flushed"
    case .repositoryFlushFailed: "repository_flush_failed"
    case .repositoryFlushSkipped: "repository_flush_skipped"
    case .serviceStopped: "service_stopped"
    case .repositoryShutdownFailed: "repository_shutdown_failed"
    case .shutdownCompleted: "shutdown_completed"
    case .shutdownFailed: "shutdown_failed"
    }
  }

  var serviceName: String {
    switch self {
    case .serviceStarted(let service), .serviceStopped(let service):
      service.rawValue
    default:
      "application"
    }
  }
}

protocol AppLifecycleLogging: Sendable {
  func record(_ event: AppLifecycleEvent) async
}

struct OSLifecycleLogger: AppLifecycleLogging {
  private let logger = Logger(subsystem: "app.fornow.ForNow", category: "lifecycle")

  func record(_ event: AppLifecycleEvent) async {
    logger.notice(
      "event=\(event.name, privacy: .public) service=\(event.serviceName, privacy: .public)"
    )
  }
}

actor InMemoryLifecycleLogger: AppLifecycleLogging {
  private var recordedEvents: [AppLifecycleEvent] = []

  func record(_ event: AppLifecycleEvent) {
    recordedEvents.append(event)
  }

  func events() -> [AppLifecycleEvent] {
    recordedEvents
  }
}
