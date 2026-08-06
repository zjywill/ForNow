import ForNowEditor
import ForNowModes
import Foundation
import XCTest

final class ModeCommandTests: XCTestCase {
  func test_UT_CMD_001A_CanonicalModeIDsAreStable() {
    XCTAssertEqual(
      ModeID.allCases.map(\.rawValue),
      ["plain", "list", "math", "sum", "average", "count", "code", "timer"]
    )
  }

  func test_UT_CMD_001B_AliasesResolveToCanonicalIDs() throws {
    let registry = try ModeAliasRegistry()

    XCTAssertEqual(registry.modeID(matching: "AVG"), .average)
    XCTAssertEqual(registry.modeID(matching: " average "), .average)
    XCTAssertEqual(registry.modeID(matching: "code"), .code)
  }

  func test_UT_CMD_001C_EachModeHasExactlyOneMainAlias() throws {
    let registry = try ModeAliasRegistry()

    for modeID in ModeID.allCases {
      let mainAlias = try XCTUnwrap(registry.mainAlias(for: modeID))
      XCTAssertTrue(registry.aliases(for: modeID).contains(mainAlias))
    }
    XCTAssertEqual(registry.mainAlias(for: .average), "avg")
  }

  func test_UT_CMD_001D_EmptyAliasesAreRejected() {
    var settings = ModeSettings()
    settings.definitions[0].aliases = ["plain", "  "]

    XCTAssertThrowsError(try ModeAliasRegistry(settings: settings)) { error in
      XCTAssertEqual(error as? ModeAliasRegistryError, .emptyAlias(.plain))
    }
  }

  func test_UT_CMD_001E_DuplicateModeDefinitionsAreRejected() {
    var settings = ModeSettings()
    settings.definitions.append(settings.definitions[0])

    XCTAssertThrowsError(try ModeAliasRegistry(settings: settings)) { error in
      XCTAssertEqual(error as? ModeAliasRegistryError, .duplicateMode(.plain))
    }
  }

  func test_UT_CMD_001F_NormalizedAliasCollisionsAreRejected() {
    var settings = ModeSettings()
    settings.definitions[1].aliases.append(" MATH ")

    XCTAssertThrowsError(try ModeAliasRegistry(settings: settings)) { error in
      XCTAssertEqual(
        error as? ModeAliasRegistryError,
        .aliasCollision("math", .list, .math)
      )
    }
  }

  func test_UT_CMD_001G_KeywordMasterSwitchDisablesInterpretationWithoutChangingSettings() throws {
    var settings = ModeSettings()
    settings.keywordInterpretationEnabled = false
    let registry = try ModeAliasRegistry(settings: settings)

    XCTAssertNil(registry.modeID(matching: "math"))
    XCTAssertEqual(registry.mainAlias(for: .math), "math")
    XCTAssertNil(ModeHeaderParser(settings: settings).parse(in: "math\n1 + 1"))
  }

  func test_UT_CMD_002A_FirstLineAliasSelectsCanonicalMode() throws {
    let header = try XCTUnwrap(ModeHeaderParser().parse(in: "math\n1 + 1"))

    XCTAssertEqual(header.modeID, .math)
    XCTAssertEqual(header.matchedAlias, "math")
    XCTAssertEqual(header.sourceRange, NSRange(location: 0, length: 4))
    XCTAssertEqual(header.bodyRange, NSRange(location: 5, length: 5))
  }

  func test_UT_CMD_002B_OptionalTitleAndRangesUseUTF16Coordinates() throws {
    let source = "  LIST: 旅行 📝  \r\n第一项"
    let header = try XCTUnwrap(ModeHeaderParser().parse(in: source))

    XCTAssertEqual(header.modeID, .list)
    XCTAssertEqual(header.title, "旅行 📝")
    XCTAssertEqual((source as NSString).substring(with: header.aliasRange), "LIST")
    XCTAssertEqual((source as NSString).substring(with: header.bodyRange), "第一项")
  }

  func test_UT_CMD_002C_InvalidKeywordsRemainOrdinaryContent() {
    XCTAssertNil(ModeHeaderParser().parse(in: "unknown: title\nbody"))
    XCTAssertNil(ModeHeaderParser().parse(in: "math extra\nbody"))
  }

  func test_UT_CMD_002D_MatchingIsCaseInsensitive() throws {
    let header = try XCTUnwrap(ModeHeaderParser().parse(in: "AvG: Trip"))

    XCTAssertEqual(header.modeID, .average)
    XCTAssertEqual(header.matchedAlias, "avg")
  }

  func test_UT_CMD_002E_RemovingHeaderReturnsSourceToPlainMode() {
    let parser = ModeHeaderParser()

    XCTAssertEqual(parser.parse(in: "sum\n1\n2")?.modeID, .sum)
    XCTAssertNil(parser.parse(in: "1\n2"))
  }

  func test_UT_CMD_002F_OnlyTheFirstLineCanSelectMode() {
    XCTAssertNil(ModeHeaderParser().parse(in: "ordinary\nmath"))
  }

  func test_UT_CMD_002G_CustomAliasesPreserveCanonicalCodeIdentity() throws {
    var settings = ModeSettings()
    let codeIndex = try XCTUnwrap(settings.definitions.firstIndex { $0.modeID == .code })
    settings.definitions[codeIndex] = ModeAliasDefinition(
      modeID: .code,
      aliases: ["source", "code"],
      mainAlias: "source"
    )

    let header = try XCTUnwrap(ModeHeaderParser(settings: settings).parse(in: "SOURCE: swift"))
    XCTAssertEqual(header.modeID, .code)
    XCTAssertEqual(header.title, "swift")
  }

  func test_UT_CMD_003_SlashEligibilityFilteringAndEditPlanningAreDeterministic() throws {
    let engine = SlashCommandEngine()

    XCTAssertTrue(engine.isEligible(in: "", selection: NSRange(location: 0, length: 0)))
    XCTAssertTrue(
      engine.isEligible(in: "math: Budget\n1 + 1", selection: NSRange(location: 0, length: 0))
    )
    XCTAssertFalse(
      engine.isEligible(in: "ordinary", selection: NSRange(location: 0, length: 0))
    )
    XCTAssertTrue(
      engine.isEligible(in: "\n", selection: NSRange(location: 1, length: 0))
    )
    XCTAssertFalse(
      engine.isEligible(in: "ordinary", selection: NSRange(location: 3, length: 0))
    )
    XCTAssertEqual(try engine.commands(matching: "av").map(\.modeID), [.average])

    let source = "math: Budget\n1 + 1"
    let plan = try XCTUnwrap(
      engine.editPlan(
        in: source,
        selection: NSRange(location: 0, length: 0),
        selecting: .list
      )
    )
    XCTAssertEqual(plan.replacementRange, NSRange(location: 0, length: 4))
    XCTAssertEqual(plan.replacement, "list")
    XCTAssertEqual(
      (source as NSString).replacingCharacters(in: plan.replacementRange, with: plan.replacement),
      "list: Budget\n1 + 1"
    )

    let bodyInvocationSource = "ordinary\n"
    let insertionPlan = try XCTUnwrap(
      engine.editPlan(
        in: bodyInvocationSource,
        selection: NSRange(location: bodyInvocationSource.utf16.count, length: 0),
        selecting: .math
      )
    )
    XCTAssertEqual(insertionPlan.replacementRange, NSRange(location: 0, length: 0))
    XCTAssertEqual(insertionPlan.replacement, "math\n")
  }

  @MainActor
  func testCustomCodeAliasControlsProjectionPasteAndCleanExport() async throws {
    var settings = ModeSettings()
    let codeIndex = try XCTUnwrap(settings.definitions.firstIndex { $0.modeID == .code })
    settings.definitions[codeIndex] = ModeAliasDefinition(
      modeID: .code,
      aliases: ["source", "code"],
      mainAlias: "source"
    )
    let source = "source: swift\nlet value = 42\nhttps://example.com/path"
    let projection = SpikeProjectionParser(modeSettings: settings).parse(
      SourceSnapshot(version: 1, text: source)
    )

    XCTAssertTrue(
      projection.decorations.contains {
        if case .style(_, .modeHeader) = $0 { return true }
        return false
      }
    )
    XCTAssertTrue(
      projection.decorations.contains {
        if case .style(_, .syntax(.keyword)) = $0 { return true }
        return false
      }
    )
    XCTAssertFalse(
      projection.decorations.contains {
        if case .link = $0 { return true }
        return false
      }
    )

    let container = ProjectionEditorContainer(initialText: source, modeSettings: settings)
    container.textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    container.pasteSettings = PasteSettings(
      stripsLeadingWhitespace: true,
      stripsListNumbers: false,
      stripsBullets: false,
      stripsMarkdown: false,
      stripsEmptyLines: false
    )
    try container.performPaste(PasteboardPayload(plainText: "\n  indented"), mode: .normal)
    XCTAssertTrue(container.textView.string.hasSuffix("\n  indented"))

    XCTAssertEqual(
      CleanExportProjection().text(
        from: source,
        policy: ExportProjectionPolicy(modeSettings: settings)
      ),
      "let value = 42\nhttps://example.com/path"
    )
  }

  func testDisabledKeywordsMakeCodeHeaderOrdinarySource() {
    var settings = ModeSettings()
    settings.keywordInterpretationEnabled = false
    let source = "code: swift\n# Heading\nhttps://example.com"
    let projection = SpikeProjectionParser(modeSettings: settings).parse(
      SourceSnapshot(version: 1, text: source)
    )

    XCTAssertFalse(
      projection.decorations.contains {
        if case .style(_, .modeHeader) = $0 { return true }
        return false
      }
    )
    XCTAssertTrue(
      projection.decorations.contains {
        if case .style(_, .heading(level: 1)) = $0 { return true }
        return false
      }
    )
    XCTAssertTrue(
      projection.decorations.contains {
        if case .link = $0 { return true }
        return false
      }
    )
    XCTAssertEqual(
      CleanExportProjection().text(
        from: source,
        policy: ExportProjectionPolicy(modeSettings: settings)
      ),
      source
    )
  }

  func testGenericModeHeaderReceivesSourceOnlyPresentation() {
    let source = "math: **Budget**\n1 + 1"
    let projection = SpikeProjectionParser().parse(SourceSnapshot(version: 1, text: source))

    XCTAssertTrue(
      projection.decorations.contains {
        if case .style(let range, .modeHeader) = $0 {
          return SourceSnapshot(version: 1, text: source).substring(in: range) == "math: **Budget**"
        }
        return false
      }
    )
    XCTAssertFalse(
      projection.decorations.contains {
        if case .style(_, .bold) = $0 { return true }
        return false
      }
    )
  }

  @MainActor
  func test_ET_CMD_002_HeaderInsertionAndReplacementEachUseOneUndoGroup() throws {
    let replacementSource = "math: Budget\n1 + 1"
    let replacementContainer = ProjectionEditorContainer(initialText: replacementSource)
    replacementContainer.textView.setSelectedRange(NSRange(location: 0, length: 0))
    let replacementPlan = try XCTUnwrap(
      SlashCommandEngine().editPlan(
        in: replacementSource,
        selection: replacementContainer.textView.selectedRange(),
        selecting: .list
      )
    )

    XCTAssertTrue(replacementContainer.performSlashCommand(replacementPlan))
    XCTAssertEqual(replacementContainer.textView.string, "list: Budget\n1 + 1")
    let replacementUndoManager = try XCTUnwrap(replacementContainer.textView.undoManager)
    replacementUndoManager.undo()
    XCTAssertEqual(replacementContainer.textView.string, replacementSource)
    replacementUndoManager.redo()
    XCTAssertEqual(replacementContainer.textView.string, "list: Budget\n1 + 1")

    let insertionContainer = ProjectionEditorContainer(initialText: "")
    insertionContainer.textView.setSelectedRange(NSRange(location: 0, length: 0))
    let insertionPlan = try XCTUnwrap(
      SlashCommandEngine().editPlan(
        in: "",
        selection: insertionContainer.textView.selectedRange(),
        selecting: .code
      )
    )
    XCTAssertTrue(insertionContainer.performSlashCommand(insertionPlan))
    XCTAssertEqual(insertionContainer.textView.string, "code")
    let insertionUndoManager = try XCTUnwrap(insertionContainer.textView.undoManager)
    insertionUndoManager.undo()
    XCTAssertEqual(insertionContainer.textView.string, "")
  }
}
