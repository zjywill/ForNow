import AppKit
import ForNowEditor
import Foundation
import XCTest

final class LinkProjectionTests: XCTestCase {
  func test_UT_EDIT_004A_HTTPAndHTTPSDetectionPreservesExactSource() {
    let first = "http://example.com/a"
    let second = "https://example.org/A%2Fb?q=%E4%B8%AD#Frag"
    let source = "first \(first)\nsecond \(second)"

    let links = links(in: source)

    XCTAssertEqual(links.map(\.originalURL), [first, second])
    XCTAssertEqual(links.map(\.duplicateIndex), [1, 1])
    XCTAssertEqual(links.map(\.identity.occurrenceIndex), [1, 1])
  }

  func test_UT_EDIT_004B_AutomaticManualAndDisabledDisplayStatesAreIndependent() throws {
    let presentation = try XCTUnwrap(links(in: "https://example.com/long/path").first)
    let duplicate = try XCTUnwrap(
      links(
        in: "https://example.com/long/path\nhttps://example.com/long/path"
      ).last
    )
    let policy = LinkDisplayPolicy()

    XCTAssertEqual(
      policy.displayText(
        for: presentation,
        settings: EditorSettings(),
        expandedIdentities: []
      ),
      "example.com/..."
    )
    XCTAssertEqual(
      policy.displayText(
        for: presentation,
        settings: EditorSettings(),
        expandedIdentities: [presentation.identity]
      ),
      presentation.originalURL
    )
    XCTAssertEqual(
      policy.displayText(
        for: duplicate,
        settings: EditorSettings(automaticallyShortensLinks: false),
        expandedIdentities: []
      ),
      duplicate.originalURL + " · 2"
    )
    XCTAssertEqual(
      policy.displayText(
        for: presentation,
        settings: EditorSettings(automaticallyShortensLinks: false),
        expandedIdentities: []
      ),
      presentation.originalURL
    )
    XCTAssertNil(
      policy.displayText(
        for: presentation,
        settings: EditorSettings(
          automaticallyShortensLinks: true,
          hyperlinkFeaturesEnabled: false
        ),
        expandedIdentities: [presentation.identity]
      )
    )
  }

  func test_UT_EDIT_004C_DuplicateIdentityAndSuffixSurviveUnrelatedEdits() {
    let url = "https://example.com/long/path"
    let original = links(in: "\(url)\nordinary text\n\(url)")
    let edited = links(in: "unrelated prefix\n\(url)\nordinary edited text\n\(url)\nend")

    XCTAssertEqual(original.map(\.identity), edited.map(\.identity))
    XCTAssertEqual(original.map(\.displayText), edited.map(\.displayText))
    XCTAssertEqual(original.map(\.duplicateIndex), [1, 2])
    XCTAssertFalse(original[0].displayText.contains("·"))
    XCTAssertTrue(original[1].displayText.hasSuffix("· 2"))
  }

  func test_UT_EDIT_004D_AllHyperlinkFeaturesOffDisablesDetection() {
    let source = "math\nhttps://example.com/path\n20 + 22 ="
    let projection = SpikeProjectionParser(
      editorSettings: EditorSettings(hyperlinkFeaturesEnabled: false)
    ).parse(SourceSnapshot(version: 1, text: source))

    XCTAssertFalse(
      projection.decorations.contains { decoration in
        if case .link = decoration { return true }
        return false
      })
    XCTAssertTrue(
      projection.decorations.contains { decoration in
        if case .result = decoration { return true }
        return false
      })
  }

  func test_UT_EDIT_004E_CodeModeHeaderDisablesLinksForWholeNote() {
    for header in ["code", " CODE: swift ", "code:typescript"] {
      XCTAssertTrue(
        links(in: "\(header)\nhttps://example.com/path").isEmpty,
        "header: \(header)"
      )
    }
    XCTAssertEqual(links(in: "plain: code\nhttps://example.com/path").count, 1)
  }

  func test_UT_EDIT_004F_FencedCodeDisablesOnlyEnclosedLinks() {
    let first = "https://outside.example/first"
    let second = "https://outside.example/second"
    let source = """
      \(first)
      ```swift
      https://inside.example/backticks
      ```
      ~~~~
      https://inside.example/tildes
      ~~~~
      \(second)
      """

    XCTAssertEqual(links(in: source).map(\.originalURL), [first, second])
  }

  func test_UT_EDIT_004G_CaretMustLeaveEitherURLBoundaryBeforePresentation() {
    let policy = LinkVisibilityPolicy()
    let range = NSRange(location: 5, length: 10)

    for location in 5...15 {
      XCTAssertFalse(
        policy.shouldPresent(
          sourceRange: range,
          selection: NSRange(location: location, length: 0)
        )
      )
    }
    XCTAssertTrue(
      policy.shouldPresent(sourceRange: range, selection: NSRange(location: 4, length: 0))
    )
    XCTAssertTrue(
      policy.shouldPresent(sourceRange: range, selection: NSRange(location: 16, length: 0))
    )
    XCTAssertFalse(
      policy.shouldPresent(sourceRange: range, selection: NSRange(location: 3, length: 4))
    )
  }

  func test_UT_EDIT_004H_ClickAndCommandClickOpenExactValidatedURL() throws {
    let source = "https://example.com/A%2Fb?q=%E4%B8%AD#Frag"
    let presentation = try XCTUnwrap(links(in: source).first)
    let policy = LinkInteractionPolicy()

    for modifiers in [LinkInteractionModifiers(), .command] {
      guard
        case .open(let url) = policy.action(
          for: presentation,
          modifiers: modifiers,
          settings: EditorSettings()
        )
      else {
        return XCTFail("Expected a validated open action")
      }
      XCTAssertEqual(url.absoluteString, source)
    }
  }

  func test_UT_EDIT_004I_CommandShiftClickTogglesStableIdentity() throws {
    let presentation = try XCTUnwrap(links(in: "https://example.com/path").first)

    XCTAssertEqual(
      LinkInteractionPolicy().action(
        for: presentation,
        modifiers: [.command, .shift],
        settings: EditorSettings()
      ),
      .toggleExpanded(presentation.identity)
    )
  }

  func test_UT_EDIT_004J_DecorationCopyReturnsExactStoredURL() throws {
    let source = "https://example.com/A%2Fb?q=one%20two"
    let snapshot = SourceSnapshot(version: 1, text: source)
    let decoration = try XCTUnwrap(
      SpikeProjectionParser().parse(snapshot).decorations.first { decoration in
        if case .link = decoration { return true }
        return false
      }
    )

    XCTAssertEqual(ProjectionCopyPolicy().copyText(for: decoration), source)
    XCTAssertEqual(snapshot.text, source)
  }

  func test_UT_EDIT_004K_LinkIdentityUsesDeterministicNonSourceDigest() throws {
    let source = "https://例子.测试/path?q=中文"
    let first = LinkIdentity(originalURL: source, occurrenceIndex: 2)
    let second = LinkIdentity(originalURL: source, occurrenceIndex: 2)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.urlDigest.count, 64)
    XCTAssertFalse(first.urlDigest.contains("例子"))
    XCTAssertEqual(first.occurrenceIndex, 2)
  }

  func test_UT_EDIT_004L_InvalidAndMaliciousSchemesNeverOpen() {
    let policy = LinkInteractionPolicy()
    let invalidSources = [
      "javascript:alert(1)",
      "file:///tmp/private",
      "ftp://example.com/file",
      "https://",
      "https://exa mple.com/path",
      "https://example.com/path\njavascript:alert(1)",
    ]

    for source in invalidSources {
      let presentation = LinkPresentation(
        originalURL: source,
        displayText: "invalid",
        duplicateIndex: 1
      )
      XCTAssertEqual(
        policy.action(
          for: presentation,
          modifiers: [],
          settings: EditorSettings()
        ),
        .ignore,
        "source: \(source)"
      )
    }
    XCTAssertTrue(links(in: "javascript:alert(1) ftp://example.com file:///tmp/a").isEmpty)
  }

  @MainActor
  func test_ET_EDIT_004_ContainerOpenToggleAndSettingsNeverMutateSource() throws {
    let source = "before https://example.com/long/path after"
    let presentation = try XCTUnwrap(links(in: source).first)
    let container = ProjectionEditorContainer(initialText: source)
    var openedURL: URL?
    var toggledIdentity: LinkIdentity?
    container.linkOpenHandler = { url in
      openedURL = url
      return true
    }
    container.linkExpansionDidToggle = { identity in
      toggledIdentity = identity
    }

    XCTAssertEqual(
      container.performLinkInteraction(presentation, modifiers: []),
      .open(
        try XCTUnwrap(URL(string: presentation.originalURL))
      ))
    XCTAssertEqual(openedURL?.absoluteString, presentation.originalURL)
    XCTAssertEqual(container.textView.string, source)

    XCTAssertEqual(
      container.performLinkInteraction(presentation, modifiers: [.command, .shift]),
      .toggleExpanded(presentation.identity)
    )
    XCTAssertEqual(toggledIdentity, presentation.identity)
    XCTAssertTrue(container.expandedLinkIdentities.contains(presentation.identity))
    XCTAssertEqual(container.textView.string, source)

    container.editorSettings = EditorSettings(hyperlinkFeaturesEnabled: false)
    openedURL = nil
    XCTAssertEqual(container.performLinkInteraction(presentation, modifiers: .command), .ignore)
    XCTAssertNil(openedURL)
    XCTAssertEqual(container.textView.string, source)
  }

  private func links(
    in source: String,
    settings: EditorSettings = EditorSettings()
  ) -> [LinkPresentation] {
    SpikeProjectionParser(editorSettings: settings)
      .parse(SourceSnapshot(version: 1, text: source))
      .decorations
      .compactMap { decoration in
        if case .link(_, let presentation) = decoration { return presentation }
        return nil
      }
  }
}
