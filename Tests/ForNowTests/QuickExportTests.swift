import ForNowCore
import ForNowEditor
import ForNowIntegrations
import ForNowModes
import Foundation
import XCTest
import ZIPFoundation

@testable import ForNow

@MainActor
final class QuickExportTests: XCTestCase {
  func test_IT_EXP_002A_TXTUsesAtomicUTF8File() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("note.txt")
    let document = makeDocument(text: "标题 📝\nplain text")

    let receipt = try await FileExportDestination(
      destinationURL: destination,
      format: .plainText
    ).export(document)

    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), document.text)
    XCTAssertEqual(receipt.resource, .file(destination))
    XCTAssertEqual(ownedTemporaryItems(in: directory), [])
  }

  func test_IT_EXP_002B_MarkdownUsesMDWithoutChangingContent() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("note.md")
    let source = "# Heading\n\n[Guide](https://example.com/full)"

    _ = try await FileExportDestination(
      destinationURL: destination,
      format: .markdown
    ).export(makeDocument(text: source))

    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), source)
  }

  func test_IT_EXP_002C_AtomicDefaultNeverOverwritesAndCleansTemporaryFile() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("existing.txt")
    try Data("original".utf8).write(to: destination)

    do {
      _ = try await FileExportDestination(
        destinationURL: destination,
        format: .plainText,
        overwritePolicy: .failIfExists
      ).export(makeDocument(text: "replacement"))
      XCTFail("An existing destination must fail without approval")
    } catch let error as ExportError {
      XCTAssertEqual(error, .destinationExists(destination.path))
    }

    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
    XCTAssertEqual(ownedTemporaryItems(in: directory), [])
  }

  func test_IT_EXP_002D_ExplicitReplacementCommitsWholeFile() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("approved.txt")
    try Data("old".utf8).write(to: destination)

    _ = try await FileExportDestination(
      destinationURL: destination,
      format: .plainText,
      overwritePolicy: .replaceExisting
    ).export(makeDocument(text: "new complete contents"))

    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new complete contents")
    XCTAssertEqual(ownedTemporaryItems(in: directory), [])
  }

  func test_IT_EXP_002E_UTF8RoundTripsCombiningEmojiAndRTL() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("unicode.txt")
    let source = "Cafe\u{301}\nمرحبا\n👩🏽‍💻\n百分号 % &"

    _ = try await FileExportDestination(
      destinationURL: destination,
      format: .plainText
    ).export(makeDocument(text: source))

    XCTAssertEqual(Data(source.utf8), try Data(contentsOf: destination))
  }

  func test_IT_EXP_002F_UnsafeFilenameCharactersAreBoundedAndUnicodeSafe() {
    let sanitizer = ExportFilenameSanitizer()
    let long = String(repeating: "字", count: 140) + "/:\u{0}"

    let sanitized = sanitizer.sanitize("  \(long).. ")

    XCTAssertLessThanOrEqual(
      sanitized.utf8.count,
      ExportFilenameSanitizer.maximumUTF8ByteCount
    )
    XCTAssertFalse(sanitized.isEmpty)
    XCTAssertFalse(sanitized.contains("/"))
    XCTAssertFalse(sanitized.contains(":"))
    XCTAssertFalse(sanitized.contains("\u{0}"))
    XCTAssertEqual(sanitizer.sanitize(" /:\u{0}. "), "---")
    XCTAssertEqual(sanitizer.sanitize("   ...   "), "Untitled")
  }

  func test_IT_EXP_002G_ZIPContainsOneUTF8TextFilePerDocument() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("notes.zip")
    let documents = [
      makeDocument(idSuffix: 1, title: "Alpha", text: "Alpha\nOne"),
      makeDocument(idSuffix: 2, title: "中文", text: "中文\n二"),
    ]

    let receipt = try await ZIPExportDestination(destinationURL: destination).export(documents)

    XCTAssertEqual(receipt.documentCount, 2)
    XCTAssertEqual(try zipEntryNames(destination), ["Alpha.txt", "中文.txt"])
    XCTAssertEqual(try zipEntryContents(destination, entry: "Alpha.txt"), "Alpha\nOne")
    XCTAssertEqual(try zipEntryContents(destination, entry: "中文.txt"), "中文\n二")
    XCTAssertEqual(ownedTemporaryItems(in: directory), [])
  }

  func test_IT_EXP_002H_ZIPDeduplicatesNamesDeterministically() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("duplicates.zip")
    let documents = [
      makeDocument(idSuffix: 1, title: "Plan", text: "one"),
      makeDocument(idSuffix: 2, title: "plan", text: "two"),
      makeDocument(idSuffix: 3, title: "Plan", text: "three"),
      makeDocument(idSuffix: 4, title: nil, text: "four"),
      makeDocument(idSuffix: 5, title: nil, text: "five"),
    ]

    _ = try await ZIPExportDestination(destinationURL: destination).export(documents)

    XCTAssertEqual(
      try zipEntryNames(destination),
      ["Plan.txt", "plan 2.txt", "Plan 3.txt", "Untitled.txt", "Untitled 2.txt"]
    )
  }

  func test_IT_EXP_002G_EnvironmentExportAllUsesRepositorySnapshotAndZIPChooser() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("all-notes.zip")
    let chooser = RecordingExportFileChooser(
      archiveSelection: ExportFileSelection(
        url: destination,
        overwritePolicy: .failIfExists
      )
    )
    let first = Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000611")!,
      body: "First\nBody one",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
      orderKey: 1
    )
    let second = Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000612")!,
      body: "Second\nBody two",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_200),
      orderKey: 2
    )
    let repository = InMemoryNoteRepository(notes: [first, second])
    let environment = AppEnvironment.test(
      repository: repository,
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      ),
      exportFileChooser: chooser
    )
    try await environment.start()

    let receipt = try await environment.performExportAll()

    XCTAssertEqual(receipt?.destination, .zip)
    XCTAssertEqual(receipt?.documentCount, 2)
    XCTAssertEqual(try zipEntryNames(destination), ["Second.txt", "First.txt"])
    XCTAssertEqual(try zipEntryContents(destination, entry: "Second.txt"), second.body)
    XCTAssertEqual(try zipEntryContents(destination, entry: "First.txt"), first.body)
    let persistedBodies = try await repository.allNotes().map(\.body)
    XCTAssertEqual(persistedBodies, [second.body, first.body])
    try await environment.shutdown()
  }

  func test_ST_EXP_002_WriteFailureLeavesSourceDestinationAndTempStateIntact() async throws {
    let directory = try temporaryDirectory()
    let missingDirectory = directory.appendingPathComponent("missing", isDirectory: true)
    let destination = missingDirectory.appendingPathComponent("note.txt")
    let document = makeDocument(text: "canonical source")
    let original = document

    await assertThrowsErrorAsync {
      _ = try await FileExportDestination(
        destinationURL: destination,
        format: .plainText
      ).export(document)
    }

    XCTAssertEqual(document, original)
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
  }

  func test_UT_EXP_003_ApplicationBuildersEncodeQueryValuesExactlyOnce() throws {
    let document = makeDocument(title: "A&B%", content: "query = A&B% / 中文", text: "full")

    let obsidian = try ApplicationExportURLBuilder.obsidian(
      document: document,
      vault: "Work & Life%"
    )
    let bear = try ApplicationExportURLBuilder.bear(document: document)
    let shortcut = try ApplicationExportURLBuilder.appleShortcut(
      document: document,
      shortcutName: "ForNow & Notes%"
    )

    XCTAssertEqual(queryValue("vault", in: obsidian), "Work & Life%")
    XCTAssertEqual(queryValue("name", in: obsidian), "A&B%")
    XCTAssertEqual(queryValue("content", in: obsidian), document.content)
    XCTAssertEqual(queryValue("title", in: bear), "A&B%")
    XCTAssertEqual(queryValue("text", in: bear), document.content)
    XCTAssertEqual(queryValue("name", in: shortcut), "ForNow & Notes%")
    XCTAssertEqual(queryValue("text", in: shortcut), document.text)
    XCTAssertTrue(obsidian.absoluteString.contains("A%26B%25"))
    XCTAssertFalse(obsidian.absoluteString.contains("%2525"))
  }

  func test_IT_EXP_003A_ObsidianChecksAvailabilityThenOpens() async throws {
    let opener = RecordingExternalURLOpener()
    let document = makeDocument(title: "Inbox", content: "Body", text: "Inbox\nBody")

    let receipt = try await ObsidianExportDestination(vault: "Work", opener: opener)
      .export(document)

    let snapshot = await opener.snapshot()
    XCTAssertEqual(snapshot.availabilityChecks.count, 1)
    XCTAssertEqual(snapshot.openedURLs.count, 1)
    XCTAssertEqual(queryValue("vault", in: snapshot.openedURLs[0]), "Work")
    XCTAssertEqual(receipt.destination, .obsidian)
  }

  func test_IT_EXP_003B_BearUsesSeparateTitleAndContent() async throws {
    let opener = RecordingExternalURLOpener()
    let document = makeDocument(title: "Title", content: "Body", text: "Title\nBody")

    _ = try await BearExportDestination(opener: opener).export(document)

    let snapshot = await opener.snapshot()
    let url = try XCTUnwrap(snapshot.openedURLs.first)
    XCTAssertEqual(queryValue("title", in: url), "Title")
    XCTAssertEqual(queryValue("text", in: url), "Body")
  }

  func test_IT_EXP_003C_AppleShortcutReceivesFullCleanText() async throws {
    let opener = RecordingExternalURLOpener()
    let document = makeDocument(title: "Title", content: "Body", text: "Title\nBody")

    _ = try await AppleShortcutExportDestination(
      shortcutName: "ForNow Notes",
      opener: opener
    ).export(document)

    let snapshot = await opener.snapshot()
    let url = try XCTUnwrap(snapshot.openedURLs.first)
    XCTAssertEqual(url.scheme, "shortcuts")
    XCTAssertEqual(queryValue("input", in: url), "text")
    XCTAssertEqual(queryValue("text", in: url), document.text)
  }

  func test_IT_EXP_003D_MissingApplicationProducesGuidanceAndNoOpen() async throws {
    let opener = RecordingExternalURLOpener(isAvailable: false)

    do {
      _ = try await BearExportDestination(opener: opener).export(makeDocument())
      XCTFail("An unavailable application must fail")
    } catch let error as ExportError {
      guard case .destinationUnavailable(let name, let guidance) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(name, "Bear")
      XCTAssertTrue(guidance.contains("Install Bear"))
    }

    let snapshot = await opener.snapshot()
    XCTAssertTrue(snapshot.openedURLs.isEmpty)
  }

  func test_IT_EXP_003E_CommandRoutingUsesConfiguredMarkdownDestination() async throws {
    let directory = try temporaryDirectory()
    let destination = directory.appendingPathComponent("configured.md")
    let chooser = RecordingExportFileChooser(
      fileSelection: ExportFileSelection(url: destination, overwritePolicy: .failIfExists)
    )
    let source = "Title\nConfigured body"
    let note = makeNote(body: source)
    let repository = InMemoryNoteRepository(notes: [note])
    let environment = AppEnvironment.test(
      repository: repository,
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      ),
      exportSettings: InMemoryExportSettingsStore(
        settings: ExportSettings(quickDestination: .markdown)
      ),
      exportFileChooser: chooser
    )
    try await environment.start()

    let receipt = try await environment.performQuickExport()

    XCTAssertEqual(receipt?.destination, .markdown)
    XCTAssertEqual(chooser.fileFormats, [.markdown])
    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), source)
    try await environment.shutdown()
  }

  func test_IT_EXP_003F_FailedExternalOpenPreservesRepositorySource() async throws {
    let source = "Title\nCanonical body"
    let note = makeNote(body: source)
    let repository = InMemoryNoteRepository(notes: [note])
    let opener = RecordingExternalURLOpener(opensSuccessfully: false)
    let environment = AppEnvironment.test(
      repository: repository,
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      ),
      exportSettings: InMemoryExportSettingsStore(
        settings: ExportSettings(quickDestination: .bear)
      ),
      externalURLOpener: opener
    )
    try await environment.start()

    await assertThrowsErrorAsync {
      _ = try await environment.performQuickExport()
    }

    let persistedNote = try await repository.note(id: note.id)
    XCTAssertEqual(persistedNote?.body, source)
    XCTAssertEqual(persistedNote?.sourceRevision, note.sourceRevision)
    XCTAssertNotNil(environment.exportErrorMessage)
    try await environment.shutdown()
  }

  func test_UT_EXP_004A_AllPlaceholdersSubstituteFromOneDocument() throws {
    let template = try ValidatedCustomURLTemplate(
      source: "drafts://x-callback-url/create?text={CONTENT}&title={TITLE}&date={DATE}"
    )
    let document = makeDocument(
      title: "Project",
      content: "Body",
      text: "Project\nBody",
      exportedAt: Date(timeIntervalSince1970: 1_704_067_200)
    )

    let url = try template.render(document: document)

    XCTAssertEqual(queryValue("text", in: url), "Body")
    XCTAssertEqual(queryValue("title", in: url), "Project")
    XCTAssertEqual(queryValue("date", in: url), "2024-01-01")
  }

  func test_UT_EXP_004B_DateIsGregorianUTC() throws {
    let template = try ValidatedCustomURLTemplate(source: "drafts://create/{DATE}")
    let date = Date(timeIntervalSince1970: 1_704_153_599)

    let url = try template.render(document: makeDocument(exportedAt: date))

    XCTAssertEqual(url.path, "/2024-01-01")
  }

  func test_UT_EXP_004C_QueryContentIsStrictAndEncodedExactlyOnce() throws {
    let template = try ValidatedCustomURLTemplate(
      source: "drafts://x-callback-url/create?text={CONTENT}"
    )
    let content = "A&B%2F + 中文"

    let url = try template.render(document: makeDocument(content: content))

    XCTAssertEqual(queryValue("text", in: url), content)
    XCTAssertTrue(url.absoluteString.contains("A%26B%252F%20%2B%20"))
    XCTAssertFalse(url.absoluteString.contains("%25252F"))
  }

  func test_UT_EXP_004D_PathContentUsesDocumentedCompatibilityTransform() throws {
    let template = try ValidatedCustomURLTemplate(source: "drafts://create/{CONTENT}")

    let url = try template.render(document: makeDocument(content: "A&B%/C"))

    XCTAssertEqual(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
      "/A+B%20percent%2FC"
    )
    XCTAssertEqual(url.path, "/A+B percent/C")
  }

  func test_UT_EXP_004E_FragmentUsesStrictEncodingWithoutPathTransform() throws {
    let template = try ValidatedCustomURLTemplate(source: "drafts://create#item-{CONTENT}")

    let url = try template.render(document: makeDocument(content: "A&B%"))

    XCTAssertEqual(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
      "item-A&B%"
    )
    XCTAssertTrue(url.absoluteString.hasSuffix("#item-A&B%25"))
  }

  func test_UT_EXP_004F_SchemeAllowlistRejectsWebFileAndUnknownSchemes() {
    for source in [
      "https://example.com/{CONTENT}",
      "file:///tmp/{CONTENT}",
      "unknown-app://create?text={CONTENT}",
    ] {
      XCTAssertThrowsError(try ValidatedCustomURLTemplate(source: source), source)
    }
    XCTAssertNoThrow(
      try ValidatedCustomURLTemplate(source: "obsidian://new?content={CONTENT}")
    )
  }

  func test_UT_EXP_004G_PlaceholdersCannotEnterAuthorityOrQueryNames() {
    for source in [
      "drafts://{TITLE}/create?text={CONTENT}",
      "drafts://create?{TITLE}={CONTENT}",
      "{TITLE}://create?text={CONTENT}",
    ] {
      XCTAssertThrowsError(try ValidatedCustomURLTemplate(source: source), source)
    }
  }

  func test_UT_EXP_004H_UnknownAndUnbalancedPlaceholdersAreRejected() {
    for source in [
      "drafts://create?text={BODY}",
      "drafts://create?text={CONTENT",
      "drafts://create?text=CONTENT}",
    ] {
      XCTAssertThrowsError(try ValidatedCustomURLTemplate(source: source), source)
    }
  }

  func test_UT_EXP_004I_TemplateSizeLimitRunsBeforeURLParsing() {
    let oversized = "drafts://create/" + String(repeating: "a", count: 4_096)

    XCTAssertThrowsError(try ValidatedCustomURLTemplate(source: oversized)) { error in
      XCTAssertEqual(
        error as? ExportError,
        .oversizedTemplate(maximumBytes: ValidatedCustomURLTemplate.maximumTemplateBytes)
      )
    }
  }

  func test_UT_EXP_004J_RenderedURLSizeLimitRejectsPayload() throws {
    let template = try ValidatedCustomURLTemplate(
      source: "drafts://create?text={CONTENT}"
    )
    let document = makeDocument(content: String(repeating: "中", count: 1_000))

    XCTAssertThrowsError(try template.render(document: document)) { error in
      XCTAssertEqual(
        error as? ExportError,
        .oversizedURL(maximumBytes: ValidatedCustomURLTemplate.maximumURLBytes)
      )
    }
  }

  func test_IT_EXP_004_ValidatedCustomDestinationOpensRenderedURLOnce() async throws {
    let opener = RecordingExternalURLOpener()
    let template = try ValidatedCustomURLTemplate(
      source: "drafts://create?text={CONTENT}&title={TITLE}"
    )

    let receipt = try await CustomURLExportDestination(template: template, opener: opener)
      .export(makeDocument(title: "Title", content: "Body"))

    let snapshot = await opener.snapshot()
    XCTAssertEqual(snapshot.availabilityChecks, snapshot.openedURLs)
    XCTAssertEqual(snapshot.openedURLs.count, 1)
    XCTAssertEqual(queryValue("text", in: snapshot.openedURLs[0]), "Body")
    XCTAssertEqual(receipt.destination, .customURL)
  }

  func test_ST_EXP_004_InvalidOversizedAndUnavailableTemplatesPerformNoOpen() async throws {
    let unavailableOpener = RecordingExternalURLOpener(isAvailable: false)
    let valid = try ValidatedCustomURLTemplate(source: "drafts://create?text={CONTENT}")
    let document = makeDocument(content: "canonical")
    let original = document

    await assertThrowsErrorAsync {
      _ = try await CustomURLExportDestination(template: valid, opener: unavailableOpener)
        .export(document)
    }
    let unavailableSnapshot = await unavailableOpener.snapshot()
    XCTAssertTrue(unavailableSnapshot.openedURLs.isEmpty)
    XCTAssertEqual(document, original)

    XCTAssertThrowsError(
      try ValidatedCustomURLTemplate(source: "https://example.com/{CONTENT}")
    )
    let oversizedDocument = makeDocument(content: String(repeating: "中", count: 1_000))
    XCTAssertThrowsError(try valid.render(document: oversizedDocument))
    let finalSnapshot = await unavailableOpener.snapshot()
    XCTAssertTrue(finalSnapshot.openedURLs.isEmpty)
  }

  func test_ExportSettingsRoundTripAndFailedSaveRollback() async throws {
    let suiteName = "QuickExportTests.\(UUID().uuidString)"
    let store = UserDefaultsExportSettingsStore(suiteName: suiteName)
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    let settings = ExportSettings(
      quickDestination: .obsidian,
      omitsKeywords: false,
      usesFirstLineAsTitle: false,
      obsidianVault: " Work ",
      appleShortcutName: " Notes ",
      customURLTemplate: " drafts://create?text={CONTENT} "
    )
    try await store.save(settings)
    let loaded = await store.load()
    XCTAssertEqual(loaded.obsidianVault, "Work")
    XCTAssertEqual(loaded.appleShortcutName, "Notes")
    XCTAssertEqual(loaded.customURLTemplate, "drafts://create?text={CONTENT}")

    let saveError = ExportError.writeFailed("fixture")
    let failingStore = InMemoryExportSettingsStore(settings: loaded, saveError: saveError)
    let environment = AppEnvironment.test(exportSettings: failingStore)
    try await environment.start()
    var changed = loaded
    changed.quickDestination = .markdown

    await assertThrowsErrorAsync {
      try await environment.updateExportSettings(changed)
    }

    XCTAssertEqual(environment.exportSettings, loaded)
    try await environment.shutdown()
  }

  private func makeDocument(
    idSuffix: Int = 1,
    title: String? = "Title",
    content: String = "Body",
    text: String = "Title\nBody",
    exportedAt: Date = Date(timeIntervalSince1970: 1_704_067_200)
  ) -> ExportDocument {
    ExportDocument(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", idSuffix))!,
      sourceRevision: 3,
      title: title,
      content: content,
      text: text,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
      exportedAt: exportedAt
    )
  }

  private func makeNote(body: String) -> Note {
    Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
      body: body,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
      orderKey: 1,
      sourceRevision: 5
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ForNowQuickExportTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  private func ownedTemporaryItems(in directory: URL) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.filter { $0.contains(".fornow-") }
  }

  private func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == name }?.value
  }

  private func zipEntryNames(_ archiveURL: URL) throws -> [String] {
    let archive = try Archive(url: archiveURL, accessMode: .read)
    return archive.map(\.path)
  }

  private func zipEntryContents(_ archiveURL: URL, entry: String) throws -> String {
    let archive = try Archive(url: archiveURL, accessMode: .read)
    guard let archiveEntry = archive[entry] else {
      throw ExportError.writeFailed("ZIP entry \(entry) is missing.")
    }
    var data = Data()
    _ = try archive.extract(archiveEntry) { chunk in
      data.append(chunk)
    }
    return String(decoding: data, as: UTF8.self)
  }
}

@MainActor
private final class RecordingExportFileChooser: ExportFileChoosing {
  private let fileSelection: ExportFileSelection?
  private let archiveSelection: ExportFileSelection?
  private(set) var fileFormats: [ExportFileFormat] = []

  init(
    fileSelection: ExportFileSelection? = nil,
    archiveSelection: ExportFileSelection? = nil
  ) {
    self.fileSelection = fileSelection
    self.archiveSelection = archiveSelection
  }

  func chooseFile(
    suggestedFilenameBase: String,
    format: ExportFileFormat
  ) async -> ExportFileSelection? {
    fileFormats.append(format)
    return fileSelection
  }

  func chooseArchive(suggestedFilenameBase: String) async -> ExportFileSelection? {
    archiveSelection
  }
}

private actor RecordingExternalURLOpener: ExternalURLOpening {
  struct Snapshot: Sendable {
    let availabilityChecks: [URL]
    let openedURLs: [URL]
  }

  private let available: Bool
  private let opensSuccessfully: Bool
  private var availabilityChecks: [URL] = []
  private var openedURLs: [URL] = []

  init(isAvailable: Bool = true, opensSuccessfully: Bool = true) {
    available = isAvailable
    self.opensSuccessfully = opensSuccessfully
  }

  func isAvailable(for url: URL) -> Bool {
    availabilityChecks.append(url)
    return available
  }

  func open(_ url: URL) -> Bool {
    openedURLs.append(url)
    return opensSuccessfully
  }

  func snapshot() -> Snapshot {
    Snapshot(availabilityChecks: availabilityChecks, openedURLs: openedURLs)
  }
}

@MainActor
private func assertThrowsErrorAsync(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected expression to throw", file: file, line: line)
  } catch {}
}
