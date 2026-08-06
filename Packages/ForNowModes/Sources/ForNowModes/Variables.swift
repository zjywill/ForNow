import Foundation

public struct VariableSuggestion: Sendable, Equatable, Identifiable {
  public let name: String
  public let replacementRange: NSRange

  public init(name: String, replacementRange: NSRange) {
    self.name = name
    self.replacementRange = replacementRange
  }

  public var id: String { name }
}

public struct VariableAutocompleteContext: Sendable, Equatable {
  public let query: String
  public let suggestions: [VariableSuggestion]

  public init(query: String, suggestions: [VariableSuggestion]) {
    self.query = query
    self.suggestions = suggestions
  }
}

public struct VariableAutocompleteEditPlan: Sendable, Equatable {
  public let expectedSource: String
  public let replacementRange: NSRange
  public let replacement: String
  public let selectionAfterEdit: NSRange

  public init(
    expectedSource: String,
    replacementRange: NSRange,
    replacement: String,
    selectionAfterEdit: NSRange
  ) {
    self.expectedSource = expectedSource
    self.replacementRange = replacementRange
    self.replacement = replacement
    self.selectionAfterEdit = selectionAfterEdit
  }
}

public struct VariableAutocompleteEngine: Sendable {
  public static let minimumQueryLength = 3
  public static let maximumSuggestions = 9

  public init() {}

  public func context(
    in source: String,
    selection: NSRange,
    modeSettings: ModeSettings = ModeSettings()
  ) -> VariableAutocompleteContext? {
    guard selection.length == 0,
      let header = ModeHeaderParser(settings: modeSettings).parse(in: source),
      header.modeID == .math,
      selection.location >= header.bodyRange.location,
      selection.location <= NSMaxRange(header.bodyRange)
    else { return nil }

    let nsSource = source as NSString
    guard selection.location <= nsSource.length else { return nil }
    let line = sourceLine(at: selection.location, in: nsSource)
    let trimmedLine = VariableSourceParser.trim(line.contentsRange, in: nsSource)
    guard trimmedLine.length > 0,
      !nsSource.substring(with: trimmedLine).hasPrefix("//")
    else { return nil }

    let colon = nsSource.range(of: ":", options: [], range: trimmedLine)
    if colon.location != NSNotFound, selection.location <= colon.location {
      return nil
    }
    let expressionStart =
      colon.location == NSNotFound ? line.contentsRange.location : NSMaxRange(colon)
    guard selection.location >= expressionStart else { return nil }
    let candidateRange = autocompleteCandidateRange(
      from: expressionStart,
      to: selection.location,
      in: nsSource
    )
    guard candidateRange.length > 0 else { return nil }
    let query = nsSource.substring(with: candidateRange)
    let normalizedQuery = VariableNamePolicy.normalize(query)
    guard VariableNamePolicy.matchingCharacterCount(normalizedQuery) >= Self.minimumQueryLength
    else {
      return nil
    }

    guard
      let parsedLines = try? VariableSourceParser.lines(
        in: nsSource,
        bodyRange: header.bodyRange,
        checksCancellation: false
      ),
      let selection = try? VariableDeclarationSelector(catalogs: .bundled).select(
        from: parsedLines,
        checksCancellation: false
      )
    else { return nil }
    let declarations = selection.assignments
    let grouped = Dictionary(grouping: declarations, by: \.normalizedName)
    let currentAssignmentName =
      colon.location == NSNotFound
      ? nil
      : VariableNamePolicy.normalize(
        nsSource.substring(
          with: VariableSourceParser.trim(
            NSRange(location: trimmedLine.location, length: colon.location - trimmedLine.location),
            in: nsSource
          )
        )
      )
    let suggestions =
      declarations
      .filter { declaration in
        grouped[declaration.normalizedName]?.count == 1
          && declaration.normalizedName != currentAssignmentName
          && declaration.normalizedName.hasPrefix(normalizedQuery)
      }
      .prefix(Self.maximumSuggestions)
      .map { VariableSuggestion(name: $0.name, replacementRange: candidateRange) }
    guard !suggestions.isEmpty else { return nil }
    return VariableAutocompleteContext(query: query, suggestions: suggestions)
  }

  public func editPlan(
    in source: String,
    context: VariableAutocompleteContext,
    selecting index: Int
  ) -> VariableAutocompleteEditPlan? {
    guard context.suggestions.indices.contains(index) else { return nil }
    let suggestion = context.suggestions[index]
    guard suggestion.replacementRange.location >= 0,
      NSMaxRange(suggestion.replacementRange) <= (source as NSString).length
    else { return nil }
    return VariableAutocompleteEditPlan(
      expectedSource: source,
      replacementRange: suggestion.replacementRange,
      replacement: suggestion.name,
      selectionAfterEdit: NSRange(
        location: suggestion.replacementRange.location + suggestion.name.utf16.count,
        length: 0
      )
    )
  }

  private func sourceLine(at location: Int, in source: NSString) -> VariableSourceLineRange {
    let lookup = min(location, max(0, source.length - 1))
    var start = 0
    var end = 0
    var contentsEnd = 0
    source.getLineStart(
      &start,
      end: &end,
      contentsEnd: &contentsEnd,
      for: NSRange(location: lookup, length: 0)
    )
    return VariableSourceLineRange(
      contentsRange: NSRange(location: start, length: contentsEnd - start),
      lineEnd: end
    )
  }

  private func autocompleteCandidateRange(
    from expressionStart: Int,
    to caret: Int,
    in source: NSString
  ) -> NSRange {
    var start = expressionStart
    var location = caret
    while location > expressionStart {
      let character = source.character(at: location - 1)
      if Self.autocompleteDelimiters.contains(character) {
        start = location
        break
      }
      location -= 1
    }
    var end = caret
    while start < end, VariableSourceParser.isHorizontalWhitespace(source.character(at: start)) {
      start += 1
    }
    while end > start, VariableSourceParser.isHorizontalWhitespace(source.character(at: end - 1)) {
      end -= 1
    }
    let range = NSRange(location: start, length: end - start)
    guard range.length > 0 else { return range }
    let candidate = source.substring(with: range)
    return VariableNamePolicy.isPartialName(candidate) ? range : NSRange(location: caret, length: 0)
  }

  private static let autocompleteDelimiters: Set<unichar> = [
    0x002B, 0x002D, 0x002A, 0x002F, 0x005E, 0x0028, 0x0029, 0x0025, 0x003D, 0x003A,
    0x0021, 0x00D7, 0x00F7,
  ]
}

private struct VariableSourceLineRange {
  let contentsRange: NSRange
  let lineEnd: Int
}

private struct VariableAssignment: Sendable {
  let name: String
  let normalizedName: String
  let nameRange: NSRange
  let expressionSource: String
  let expressionRange: NSRange
  let displayExpressionRange: NSRange
  let anchorUTF16Offset: Int?
  let sourceOrder: Int
}

private struct VariableSourceLine: Sendable {
  let sourceOrder: Int
  let expressionSource: String
  let expressionRange: NSRange
  let displayExpressionRange: NSRange
  let anchorUTF16Offset: Int?
  let assignment: VariableAssignment?
  let invalidDeclarationRange: NSRange?
}

private enum VariableNamePolicy {
  static let maximumNameLength = 64

  static func normalize(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping
      .split(whereSeparator: isHorizontalWhitespace)
      .joined(separator: " ")
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  static func normalizeDisplayName(_ value: String) -> String {
    value.split(whereSeparator: isHorizontalWhitespace).joined(separator: " ")
  }

  static func isValid(_ value: String) -> Bool {
    let normalized = normalize(value)
    guard !normalized.isEmpty, normalized.utf16.count <= maximumNameLength else { return false }
    var containsLetter = false
    for scalar in normalized.unicodeScalars {
      switch scalar.properties.generalCategory {
      case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
        containsLetter = true
      case .decimalNumber:
        break
      case .spaceSeparator where scalar.value == 0x20:
        break
      default:
        return false
      }
    }
    return containsLetter
  }

  static func isPartialName(_ value: String) -> Bool {
    !value.isEmpty
      && value.allSatisfy { character in
        character.isLetter || character.isNumber || isHorizontalWhitespace(character)
      }
  }

  static func matchingCharacterCount(_ value: String) -> Int {
    value.reduce(into: 0) { count, character in
      if character.isLetter || character.isNumber { count += 1 }
    }
  }

  private static func isHorizontalWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t"
  }
}

private enum VariableSourceParser {
  static let maximumDeclarations = 128

  static func lines(
    in source: NSString,
    bodyRange: NSRange,
    checksCancellation: Bool
  ) throws -> [VariableSourceLine] {
    var parsed: [VariableSourceLine] = []
    var location = bodyRange.location
    var sourceOrder = 0
    while location < NSMaxRange(bodyRange) {
      if checksCancellation, sourceOrder.isMultiple(of: 32) {
        try Task.checkCancellation()
      }
      var lineStart = 0
      var lineEnd = 0
      var contentsEnd = 0
      source.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      let contentsRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
      if let line = parseLine(
        source,
        contentsRange: contentsRange,
        sourceOrder: sourceOrder
      ) {
        parsed.append(line)
      }
      let nextLocation = min(lineEnd, NSMaxRange(bodyRange))
      location = nextLocation > location ? nextLocation : location + 1
      sourceOrder += 1
    }
    return parsed
  }

  static func trim(_ range: NSRange, in source: NSString) -> NSRange {
    var start = range.location
    var end = NSMaxRange(range)
    while start < end, isHorizontalWhitespace(source.character(at: start)) { start += 1 }
    while end > start, isHorizontalWhitespace(source.character(at: end - 1)) { end -= 1 }
    return NSRange(location: start, length: end - start)
  }

  static func isHorizontalWhitespace(_ character: unichar) -> Bool {
    character == 0x0020 || character == 0x0009
  }

  private static func parseLine(
    _ source: NSString,
    contentsRange: NSRange,
    sourceOrder: Int
  ) -> VariableSourceLine? {
    let trimmedRange = trim(contentsRange, in: source)
    guard trimmedRange.length > 0,
      !source.substring(with: trimmedRange).hasPrefix("//")
    else { return nil }

    let hasTrailingEquals = source.character(at: NSMaxRange(trimmedRange) - 1) == 0x003D
    let anchor = hasTrailingEquals ? NSMaxRange(trimmedRange) : nil
    let coreRange = trim(
      NSRange(
        location: trimmedRange.location,
        length: trimmedRange.length - (hasTrailingEquals ? 1 : 0)
      ),
      in: source
    )
    let colon = source.range(of: ":", options: [], range: coreRange)
    if colon.location != NSNotFound {
      let nameRange = trim(
        NSRange(location: coreRange.location, length: colon.location - coreRange.location),
        in: source
      )
      let expressionRange = trim(
        NSRange(location: NSMaxRange(colon), length: NSMaxRange(coreRange) - NSMaxRange(colon)),
        in: source
      )
      let name = source.substring(with: nameRange)
      let valid =
        nameRange.length > 0
        && expressionRange.length > 0
        && VariableNamePolicy.isValid(name)
      guard valid else {
        return VariableSourceLine(
          sourceOrder: sourceOrder,
          expressionSource: "",
          expressionRange: expressionRange,
          displayExpressionRange: coreRange,
          anchorUTF16Offset: anchor,
          assignment: nil,
          invalidDeclarationRange: coreRange
        )
      }
      let assignment = VariableAssignment(
        name: VariableNamePolicy.normalizeDisplayName(name),
        normalizedName: VariableNamePolicy.normalize(name),
        nameRange: nameRange,
        expressionSource: source.substring(with: expressionRange),
        expressionRange: expressionRange,
        displayExpressionRange: coreRange,
        anchorUTF16Offset: anchor,
        sourceOrder: sourceOrder
      )
      return VariableSourceLine(
        sourceOrder: sourceOrder,
        expressionSource: assignment.expressionSource,
        expressionRange: expressionRange,
        displayExpressionRange: coreRange,
        anchorUTF16Offset: anchor,
        assignment: assignment,
        invalidDeclarationRange: nil
      )
    }

    guard hasTrailingEquals else { return nil }
    return VariableSourceLine(
      sourceOrder: sourceOrder,
      expressionSource: source.substring(with: coreRange),
      expressionRange: coreRange,
      displayExpressionRange: coreRange,
      anchorUTF16Offset: anchor,
      assignment: nil,
      invalidDeclarationRange: nil
    )
  }
}

private struct VariableReference: Sendable {
  let normalizedName: String
  let range: NSRange
  let sourceOrder: Int
}

private struct VariableReferenceMatcher: @unchecked Sendable {
  private static let maximumNamesPerExpression = 128

  struct Name: Sendable {
    let displayName: String
    let normalizedName: String
    let sourceOrder: Int
  }

  private struct CompiledExpression {
    let names: [Name]
    let expression: NSRegularExpression
  }

  private let compiledExpressions: [CompiledExpression]

  init(names: [Name]) {
    let sortedNames = names.sorted {
      let leftLength = $0.displayName.utf16.count
      let rightLength = $1.displayName.utf16.count
      if leftLength != rightLength { return leftLength > rightLength }
      return $0.sourceOrder < $1.sourceOrder
    }
    var expressions: [CompiledExpression] = []
    for start in stride(
      from: 0,
      to: sortedNames.count,
      by: Self.maximumNamesPerExpression
    ) {
      let end = min(start + Self.maximumNamesPerExpression, sortedNames.count)
      let chunk = Array(sortedNames[start..<end])
      let alternatives = chunk.map { name in
        name.displayName
          .split(whereSeparator: { $0 == " " || $0 == "\t" })
          .map { NSRegularExpression.escapedPattern(for: String($0)) }
          .joined(separator: #"[\t ]+"#)
      }
      let expression = try! NSRegularExpression(
        pattern: #"(?=(?<![\p{L}\p{N}_])("#
          + alternatives.map { "(\($0))" }.joined(separator: "|")
          + #")(?![\p{L}\p{N}_]))"#,
        options: [.caseInsensitive]
      )
      expressions.append(CompiledExpression(names: chunk, expression: expression))
    }
    compiledExpressions = expressions
  }

  func references(in source: String) -> [VariableReference] {
    let fullRange = NSRange(location: 0, length: (source as NSString).length)
    var candidates: [VariableReference] = []
    for compiled in compiledExpressions {
      compiled.expression.enumerateMatches(in: source, range: fullRange) { match, _, _ in
        guard let match else { return }
        for index in compiled.names.indices {
          let range = match.range(at: index + 2)
          guard range.location != NSNotFound else { continue }
          candidates.append(
            VariableReference(
              normalizedName: compiled.names[index].normalizedName,
              range: range,
              sourceOrder: compiled.names[index].sourceOrder
            )
          )
          return
        }
      }
    }
    candidates.sort {
      if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
      if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
      return $0.sourceOrder < $1.sourceOrder
    }
    var references: [VariableReference] = []
    var nextAvailableLocation = 0
    for candidate in candidates where candidate.range.location >= nextAvailableLocation {
      references.append(candidate)
      nextAvailableLocation = NSMaxRange(candidate.range)
    }
    return references
  }
}

private struct VariableDeclarationSelection {
  let assignments: [VariableAssignment]
  let fallbackSourceOrders: Set<Int>
  let excessiveSourceOrders: Set<Int>
}

private struct VariableDeclarationSelector {
  let catalogs: ConversionCatalogs

  func select(
    from lines: [VariableSourceLine],
    checksCancellation: Bool
  ) throws -> VariableDeclarationSelection {
    if checksCancellation { try Task.checkCancellation() }
    let candidates = lines.compactMap(\.assignment)
    let groups = Dictionary(grouping: candidates, by: \.normalizedName)
    let matcher = VariableReferenceMatcher(
      names: groups.values.compactMap { group in
        guard let first = group.min(by: { $0.sourceOrder < $1.sourceOrder }) else { return nil }
        return VariableReferenceMatcher.Name(
          displayName: first.name,
          normalizedName: first.normalizedName,
          sourceOrder: first.sourceOrder
        )
      }
    )
    if checksCancellation { try Task.checkCancellation() }
    var referencesBySourceOrder: [Int: [VariableReference]] = [:]
    var referencedNames = Set<String>()
    for (index, line) in lines.enumerated() {
      if checksCancellation, index.isMultiple(of: 32) {
        try Task.checkCancellation()
      }
      let references = matcher.references(in: line.expressionSource)
      referencedNames.formUnion(references.map(\.normalizedName))
      if line.assignment != nil {
        referencesBySourceOrder[line.sourceOrder] = references
      }
    }
    let disambiguator = VariableDeclarationDisambiguator(catalogs: catalogs)
    var selected: [VariableAssignment] = []
    for (index, candidate) in candidates.enumerated() {
      if checksCancellation, index.isMultiple(of: 32) {
        try Task.checkCancellation()
      }
      if referencedNames.contains(candidate.normalizedName)
        || disambiguator.isUnambiguous(
          candidate.expressionSource,
          variableReferences: referencesBySourceOrder[candidate.sourceOrder] ?? []
        )
      {
        selected.append(candidate)
      }
    }
    let selectedOrders = Set(selected.map(\.sourceOrder))
    let accepted = Array(selected.prefix(VariableSourceParser.maximumDeclarations))
    let excessiveSourceOrders = Set(
      selected.dropFirst(VariableSourceParser.maximumDeclarations).map(\.sourceOrder)
    )
    return VariableDeclarationSelection(
      assignments: accepted,
      fallbackSourceOrders: Set(candidates.map(\.sourceOrder)).subtracting(selectedOrders),
      excessiveSourceOrders: excessiveSourceOrders
    )
  }
}

private struct VariableDeclarationDisambiguator {
  let allowedWords: Set<String>

  init(catalogs: ConversionCatalogs) {
    var words: Set<String> = [
      "x", "of", "sqrt", "log", "log2", "ceil", "floor", "in", "to",
    ]
    for unit in catalogs.units.units {
      for alias in unit.aliases {
        words.formUnion(Self.words(in: alias))
      }
    }
    for currency in catalogs.currencies.currencies {
      words.insert(currency.code.rawValue.lowercased(with: Self.posixLocale))
      for alias in currency.aliases {
        words.formUnion(Self.words(in: alias))
      }
    }
    allowedWords = words
  }

  func isUnambiguous(
    _ source: String,
    variableReferences: [VariableReference]
  ) -> Bool {
    let range = NSRange(location: 0, length: (source as NSString).length)
    for match in Self.wordExpression.matches(in: source, range: range) {
      if variableReferences.contains(where: {
        NSIntersectionRange($0.range, match.range).length == match.range.length
      }) {
        continue
      }
      let word = (source as NSString).substring(with: match.range)
        .lowercased(with: Self.posixLocale)
      if !allowedWords.contains(word) { return false }
    }
    return true
  }

  private static func words(in source: String) -> Set<String> {
    let nsSource = source as NSString
    let range = NSRange(location: 0, length: nsSource.length)
    return Set(
      wordExpression.matches(in: source, range: range).map {
        nsSource.substring(with: $0.range).lowercased(with: posixLocale)
      }
    )
  }

  private static let posixLocale = Locale(identifier: "en_US_POSIX")
  private static let wordExpression = try! NSRegularExpression(pattern: #"[\p{L}][\p{L}\p{N}]*"#)
}

private struct VariableStoredValue: Sendable {
  let canonicalValue: String
  let dependencyNames: [String]
  let evaluation: BasicMathLineEvaluation
}

private enum VariableResolution: Sendable {
  case success(VariableStoredValue)
  case failure(BasicMathDiagnostic)
}

struct VariableDocumentEvaluator: Sendable {
  private static let maximumDependencyDepth = 64

  let settings: MathSettings
  let locale: MathDecimalLocale
  let catalogs: ConversionCatalogs
  let currencyContext: CurrencyConversionContext

  func evaluate(
    source: String,
    bodyRange: NSRange,
    checksCancellation: Bool
  ) throws -> [BasicMathLineEvaluation] {
    let lines = try VariableSourceParser.lines(
      in: source as NSString,
      bodyRange: bodyRange,
      checksCancellation: checksCancellation
    )
    var state = VariableEvaluationState(
      source: source,
      lines: lines,
      settings: settings,
      locale: locale,
      catalogs: catalogs,
      currencyContext: currencyContext
    )
    return try state.evaluate(checksCancellation: checksCancellation)
  }

  private struct VariableEvaluationState {
    let source: String
    let lines: [VariableSourceLine]
    let settings: MathSettings
    let locale: MathDecimalLocale
    let catalogs: ConversionCatalogs
    let currencyContext: CurrencyConversionContext

    var declarations: [String: VariableAssignment] = [:]
    var declarationGroups: [String: [VariableAssignment]] = [:]
    var matcher = VariableReferenceMatcher(names: [])
    var directReferences: [String: [VariableReference]] = [:]
    var cyclicNames: Set<String> = []
    var excessiveDepthNames: Set<String> = []
    var resolutions: [String: VariableResolution] = [:]
    var fallbackSourceOrders: Set<Int> = []
    var excessiveSourceOrders: Set<Int> = []

    mutating func evaluate(checksCancellation: Bool) throws -> [BasicMathLineEvaluation] {
      try prepareGraph(checksCancellation: checksCancellation)
      let orderedDeclarations = declarations.values.sorted { $0.sourceOrder < $1.sourceOrder }
      for (index, declaration) in orderedDeclarations.enumerated() {
        if checksCancellation, index.isMultiple(of: 32) { try Task.checkCancellation() }
        _ = resolve(declaration.normalizedName, depth: 0)
      }

      var evaluations: [BasicMathLineEvaluation] = []
      for (index, line) in lines.enumerated() {
        if checksCancellation, index.isMultiple(of: 32) { try Task.checkCancellation() }
        if let invalidRange = line.invalidDeclarationRange {
          evaluations.append(
            .diagnostic(
              diagnostic(
                .variableInvalidDeclaration,
                range: invalidRange,
                message: "Variable declarations need a valid name and expression."
              )
            )
          )
          continue
        }
        if let assignment = line.assignment {
          if fallbackSourceOrders.contains(assignment.sourceOrder) {
            guard let anchor = assignment.anchorUTF16Offset else { continue }
            let fallbackLine = VariableSourceLine(
              sourceOrder: line.sourceOrder,
              expressionSource: (source as NSString).substring(
                with: assignment.displayExpressionRange
              ),
              expressionRange: assignment.displayExpressionRange,
              displayExpressionRange: assignment.displayExpressionRange,
              anchorUTF16Offset: anchor,
              assignment: nil,
              invalidDeclarationRange: nil
            )
            evaluations.append(evaluateOrdinaryLine(fallbackLine, anchor: anchor))
            continue
          }
          if excessiveSourceOrders.contains(assignment.sourceOrder) {
            evaluations.append(
              .diagnostic(
                diagnostic(
                  .variableResourceLimit,
                  range: assignment.nameRange,
                  message: "A Math note supports at most 128 variable declarations."
                )
              )
            )
            continue
          }
          if (declarationGroups[assignment.normalizedName]?.count ?? 0) > 1 {
            evaluations.append(
              .diagnostic(
                diagnostic(
                  .variableDuplicateName,
                  range: assignment.nameRange,
                  message: "Variable names must be unique within a Math note."
                )
              )
            )
            continue
          }
          guard let resolution = resolutions[assignment.normalizedName] else { continue }
          switch resolution {
          case .success(let stored):
            if assignment.anchorUTF16Offset != nil { evaluations.append(stored.evaluation) }
          case .failure(let diagnostic):
            evaluations.append(.diagnostic(diagnostic))
          }
          continue
        }
        guard let anchor = line.anchorUTF16Offset else { continue }
        evaluations.append(evaluateOrdinaryLine(line, anchor: anchor))
      }
      return evaluations
    }

    mutating func prepareGraph(checksCancellation: Bool) throws {
      let selection = try VariableDeclarationSelector(catalogs: catalogs).select(
        from: lines,
        checksCancellation: checksCancellation
      )
      fallbackSourceOrders = selection.fallbackSourceOrders
      excessiveSourceOrders = selection.excessiveSourceOrders
      let assignments = selection.assignments
      declarationGroups = Dictionary(grouping: assignments, by: \.normalizedName)
      for (name, group) in declarationGroups where group.count == 1 {
        declarations[name] = group[0]
      }
      matcher = VariableReferenceMatcher(
        names: declarationGroups.values.compactMap { group in
          guard let first = group.min(by: { $0.sourceOrder < $1.sourceOrder }) else { return nil }
          return VariableReferenceMatcher.Name(
            displayName: first.name,
            normalizedName: first.normalizedName,
            sourceOrder: first.sourceOrder
          )
        }
      )
      for (name, declaration) in declarations {
        directReferences[name] = matcher.references(in: declaration.expressionSource)
      }
      cyclicNames = findCycles()
      excessiveDepthNames = findExcessiveDepthNames()
    }

    mutating func resolve(_ name: String, depth: Int) -> VariableResolution {
      if let resolution = resolutions[name] { return resolution }
      guard let declaration = declarations[name] else {
        return .failure(
          diagnostic(
            .variableDependencyUnavailable,
            range: NSRange(location: 0, length: 0),
            message: "A referenced variable is unavailable."
          )
        )
      }
      if cyclicNames.contains(name) {
        let failure = VariableResolution.failure(
          diagnostic(
            .variableCycle,
            range: declaration.nameRange,
            message: "The variable dependency graph contains a cycle."
          )
        )
        resolutions[name] = failure
        return failure
      }
      if excessiveDepthNames.contains(name)
        || depth >= VariableDocumentEvaluator.maximumDependencyDepth
      {
        let failure = VariableResolution.failure(
          diagnostic(
            .variableDepthLimit,
            range: declaration.nameRange,
            message: "The variable dependency depth exceeds 64 declarations."
          )
        )
        resolutions[name] = failure
        return failure
      }

      let references = directReferences[name] ?? []
      if let duplicate = references.first(where: {
        (declarationGroups[$0.normalizedName]?.count ?? 0) > 1
      }) {
        let failure = VariableResolution.failure(
          diagnostic(
            .variableDuplicateName,
            range: offset(duplicate.range, by: declaration.expressionRange.location),
            message: "A referenced variable has duplicate declarations."
          )
        )
        resolutions[name] = failure
        return failure
      }

      var values: [String: VariableStoredValue] = [:]
      for referenceName in uniqueNames(in: references) {
        switch resolve(referenceName, depth: depth + 1) {
        case .success(let value):
          values[referenceName] = value
        case .failure:
          let failure = VariableResolution.failure(
            diagnostic(
              .variableDependencyUnavailable,
              range: declaration.expressionRange,
              message: "A variable dependency could not be evaluated."
            )
          )
          resolutions[name] = failure
          return failure
        }
      }

      let substituted = substitute(
        declaration.expressionSource,
        references: references,
        values: values
      )
      let dependencyNames = orderedDependencyNames(references: references, values: values)
      let evaluation = evaluateExpression(
        source: substituted,
        originalSource: declaration.expressionSource,
        expressionRange: declaration.expressionRange,
        displayExpressionRange: declaration.displayExpressionRange,
        anchor: declaration.anchorUTF16Offset ?? NSMaxRange(declaration.expressionRange),
        dependencyNames: dependencyNames
      )
      switch evaluation {
      case .result(let result):
        let stored = VariableStoredValue(
          canonicalValue: result.canonicalValue,
          dependencyNames: dependencyNames,
          evaluation: evaluation
        )
        let success = VariableResolution.success(stored)
        resolutions[name] = success
        return success
      case .diagnostic(let original):
        let failure = VariableResolution.failure(
          BasicMathDiagnostic(
            code: original.code,
            sourceRange: declaration.expressionRange,
            message: original.message
          )
        )
        resolutions[name] = failure
        return failure
      }
    }

    mutating func evaluateOrdinaryLine(
      _ line: VariableSourceLine,
      anchor: Int
    ) -> BasicMathLineEvaluation {
      guard line.expressionRange.length > 0 else {
        return .diagnostic(
          diagnostic(
            .emptyExpression,
            range: NSRange(location: max(0, anchor - 1), length: 1),
            message: "Enter an expression before the equals sign."
          )
        )
      }
      let references = matcher.references(in: line.expressionSource)
      if let duplicate = references.first(where: {
        (declarationGroups[$0.normalizedName]?.count ?? 0) > 1
      }) {
        return .diagnostic(
          diagnostic(
            .variableDuplicateName,
            range: offset(duplicate.range, by: line.expressionRange.location),
            message: "A referenced variable has duplicate declarations."
          )
        )
      }
      var values: [String: VariableStoredValue] = [:]
      for name in uniqueNames(in: references) {
        switch resolve(name, depth: 0) {
        case .success(let value):
          values[name] = value
        case .failure(let failure):
          let code: BasicMathDiagnosticCode =
            failure.code == .variableCycle
            ? .variableCycle : .variableDependencyUnavailable
          return .diagnostic(
            diagnostic(
              code,
              range: line.expressionRange,
              message: code == .variableCycle
                ? "The referenced variable belongs to a dependency cycle."
                : "A variable dependency could not be evaluated."
            )
          )
        }
      }
      let substituted = substitute(line.expressionSource, references: references, values: values)
      return evaluateExpression(
        source: substituted,
        originalSource: line.expressionSource,
        expressionRange: line.expressionRange,
        displayExpressionRange: line.displayExpressionRange,
        anchor: anchor,
        dependencyNames: orderedDependencyNames(references: references, values: values)
      )
    }

    func evaluateExpression(
      source expressionSource: String,
      originalSource: String,
      expressionRange: NSRange,
      displayExpressionRange: NSRange,
      anchor: Int,
      dependencyNames: [String]
    ) -> BasicMathLineEvaluation {
      let wasSubstituted = expressionSource != originalSource
      let evaluationRange =
        wasSubstituted
        ? NSRange(location: 0, length: (expressionSource as NSString).length)
        : expressionRange
      let evaluationAnchor = wasSubstituted ? NSMaxRange(evaluationRange) : anchor
      let evaluation: BasicMathLineEvaluation
      if let conversion = ConversionLineParser(
        settings: settings,
        locale: locale,
        catalogs: catalogs,
        context: currencyContext
      ).evaluate(
        source: expressionSource,
        sourceRange: evaluationRange,
        anchorUTF16Offset: evaluationAnchor
      ) {
        evaluation = conversion
      } else {
        do {
          let parsed = try BasicMathExpressionEngine(locale: locale).evaluate(
            expressionSource,
            sourceRange: evaluationRange
          )
          let formatter = BasicMathFormatter(settings: settings, locale: locale)
          let canonical = formatter.canonical(parsed.value)
          evaluation = .result(
            BasicMathResult(
              expressionRange: evaluationRange,
              anchorUTF16Offset: evaluationAnchor,
              expression: parsed.expression,
              canonicalValue: canonical,
              displayText: formatter.display(parsed.value),
              copiedText: canonical
            )
          )
        } catch let diagnostic as BasicMathDiagnostic {
          evaluation = .diagnostic(diagnostic)
        } catch {
          evaluation = .diagnostic(
            diagnostic(
              .unexpectedToken,
              range: evaluationRange,
              message: "The expression could not be parsed."
            )
          )
        }
      }

      switch evaluation {
      case .result(let result):
        return .result(
          BasicMathResult(
            expressionRange: displayExpressionRange,
            anchorUTF16Offset: anchor,
            expression: result.expression,
            canonicalValue: result.canonicalValue,
            displayText: result.displayText,
            copiedText: result.copiedText,
            dependencyIDs: dependencyNames
          )
        )
      case .diagnostic(let diagnostic) where wasSubstituted:
        return .diagnostic(
          BasicMathDiagnostic(
            code: diagnostic.code,
            sourceRange: expressionRange,
            message: diagnostic.message
          )
        )
      case .diagnostic:
        return evaluation
      }
    }

    func substitute(
      _ source: String,
      references: [VariableReference],
      values: [String: VariableStoredValue]
    ) -> String {
      let substituted = NSMutableString(string: source)
      for reference in references.reversed() {
        guard let value = values[reference.normalizedName] else { continue }
        substituted.replaceCharacters(in: reference.range, with: "(\(value.canonicalValue))")
      }
      return substituted as String
    }

    func orderedDependencyNames(
      references: [VariableReference],
      values: [String: VariableStoredValue]
    ) -> [String] {
      var normalizedNames = Set<String>()
      for reference in references {
        normalizedNames.insert(reference.normalizedName)
        if let value = values[reference.normalizedName] {
          for dependency in value.dependencyNames {
            normalizedNames.insert(VariableNamePolicy.normalize(dependency))
          }
        }
      }
      return declarations.values
        .filter { normalizedNames.contains($0.normalizedName) }
        .sorted { $0.sourceOrder < $1.sourceOrder }
        .map(\.name)
    }

    func uniqueNames(in references: [VariableReference]) -> [String] {
      var seen = Set<String>()
      return references.compactMap {
        seen.insert($0.normalizedName).inserted ? $0.normalizedName : nil
      }
    }

    func findCycles() -> Set<String> {
      enum VisitState { case visiting, visited }
      var states: [String: VisitState] = [:]
      var stack: [String] = []
      var cycles = Set<String>()

      func visit(_ name: String) {
        if states[name] == .visited { return }
        if states[name] == .visiting {
          if let index = stack.firstIndex(of: name) {
            cycles.formUnion(stack[index...])
          }
          return
        }
        states[name] = .visiting
        stack.append(name)
        for dependency in directReferences[name] ?? []
        where declarations[dependency.normalizedName] != nil {
          visit(dependency.normalizedName)
        }
        _ = stack.popLast()
        states[name] = .visited
      }

      for name in declarations.keys.sorted() { visit(name) }
      return cycles
    }

    func findExcessiveDepthNames() -> Set<String> {
      var depths: [String: Int] = [:]

      func depth(_ name: String, visiting: Set<String>) -> Int {
        if let depth = depths[name] { return depth }
        guard !visiting.contains(name), !cyclicNames.contains(name) else { return 0 }
        var visiting = visiting
        visiting.insert(name)
        let dependencyDepth =
          (directReferences[name] ?? [])
          .filter { declarations[$0.normalizedName] != nil }
          .map { depth($0.normalizedName, visiting: visiting) }
          .max() ?? 0
        let resolvedDepth = min(
          VariableDocumentEvaluator.maximumDependencyDepth + 1,
          dependencyDepth + 1
        )
        depths[name] = resolvedDepth
        return resolvedDepth
      }

      for name in declarations.keys {
        _ = depth(name, visiting: [])
      }
      return Set(
        depths.compactMap { name, depth in
          depth > VariableDocumentEvaluator.maximumDependencyDepth ? name : nil
        }
      )
    }

    func diagnostic(
      _ code: BasicMathDiagnosticCode,
      range: NSRange,
      message: String
    ) -> BasicMathDiagnostic {
      BasicMathDiagnostic(code: code, sourceRange: range, message: message)
    }

    func offset(_ range: NSRange, by amount: Int) -> NSRange {
      NSRange(location: range.location + amount, length: range.length)
    }
  }
}
