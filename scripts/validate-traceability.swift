#!/usr/bin/env swift
import Foundation

struct Traceability: Decodable {
  let version: Int
  let scope: String
  let reviewed: String
  let undocumentedMarker: String
  let evidence: [String: EvidenceEntry]
  let requirements: [String: RequirementEntry]
}

struct EvidenceEntry: Decodable {
  let title: String
  let confidence: String
  let sourceDescription: String
  let sourceURLs: [String]
  let requirements: [String]
}

struct RequirementEntry: Decodable {
  let title: String
  let classification: String
  let sourceDescription: String
  let evidence: [String]
  let decisions: [String]
  let release: String
  let tests: [String]
  let manualURLs: [String]
}

let testIDPattern = "(?:UT|IT|ET|UIT|MT|PT|ST|SOAK|FAULT)-[A-Z0-9]+-[0-9]{3}[A-Z]?"

func captures(_ pattern: String, in text: String) -> [[String]] {
  guard let expression = try? NSRegularExpression(pattern: pattern) else {
    return []
  }
  let fullRange = NSRange(text.startIndex..., in: text)
  return expression.matches(in: text, range: fullRange).map { match in
    (1..<match.numberOfRanges).compactMap { index in
      let range = match.range(at: index)
      guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
        return nil
      }
      return String(text[swiftRange])
    }
  }
}

func capturedSet(_ pattern: String, in text: String) -> Set<String> {
  Set(captures(pattern, in: text).compactMap(\.first))
}

func expandRange(first: String, last: String) -> [String]? {
  let letterPattern = #"\A(.+-[0-9]{3})([A-Z])\z"#
  let firstLetter = captures(letterPattern, in: first).first
  let lastLetter = captures(letterPattern, in: last).first
  if let firstLetter, let lastLetter, firstLetter.count == 2, lastLetter.count == 2,
    firstLetter[0] == lastLetter[0], let start = firstLetter[1].unicodeScalars.first?.value,
    let end = lastLetter[1].unicodeScalars.first?.value, start <= end
  {
    return (start...end).compactMap { value in
      UnicodeScalar(value).map { "\(firstLetter[0])\(Character($0))" }
    }
  }

  let numberPattern = #"\A(.+-)([0-9]{3})\z"#
  let firstNumber = captures(numberPattern, in: first).first
  let lastNumber = captures(numberPattern, in: last).first
  if let firstNumber, let lastNumber, firstNumber.count == 2, lastNumber.count == 2,
    firstNumber[0] == lastNumber[0], let start = Int(firstNumber[1]),
    let end = Int(lastNumber[1]), start <= end
  {
    return (start...end).map { String(format: "%@%03d", firstNumber[0], $0) }
  }
  return nil
}

func expandedTestIDs(in text: String) -> Set<String> {
  var ids = capturedSet("`(\(testIDPattern))`", in: text)
  let ranges = captures("`(\(testIDPattern))`\\s+through\\s+`(\(testIDPattern))`", in: text)
  for range in ranges where range.count == 2 {
    if let expandedRange = expandRange(first: range[0], last: range[1]) {
      for id in expandedRange {
        ids.insert(id)
      }
    }
  }
  return ids
}

func testRows(in matrix: String) -> [String: Set<String>] {
  var rows: [String: Set<String>] = [:]
  for line in matrix.split(separator: "\n", omittingEmptySubsequences: false) {
    let fields = line.split(separator: "|", omittingEmptySubsequences: false)
    guard fields.count >= 4 else { continue }
    let requirementField = String(fields[1])
    guard
      let requirementID = captures("`(FR-[A-Z0-9-]+-[0-9]{3})`", in: requirementField)
        .first?.first
    else { continue }
    rows[requirementID] = expandedTestIDs(in: String(fields[2]))
  }
  return rows
}

func reportDifference(
  defined: Set<String>, traced: Set<String>, kind: String, errors: inout [String]
) {
  for id in defined.subtracting(traced).sorted() {
    errors.append("\(id) is defined but missing from traced \(kind)")
  }
  for id in traced.subtracting(defined).sorted() {
    errors.append("\(id) is traced as \(kind) but not defined")
  }
}

let root = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
let environment = ProcessInfo.processInfo.environment
let traceURL =
  environment["TRACEABILITY_FILE"].map { URL(fileURLWithPath: $0) }
  ?? root.appendingPathComponent("docs/traceability.yml")

func read(_ relativePath: String) throws -> String {
  try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

do {
  let traceData = try Data(contentsOf: traceURL)
  let trace = try JSONDecoder().decode(Traceability.self, from: traceData)
  let ledger = try read("docs/00_SOURCE_LEDGER.md")
  let spec = try read("docs/01_PRODUCT_SPEC.md")
  let matrix = try read("docs/04_TEST_MATRIX.md")
  let walkthrough = try read("docs/06_MANUAL_WALKTHROUGH.md")
  var errors: [String] = []

  if trace.version != 1 { errors.append("unsupported traceability version \(trace.version)") }
  if trace.scope != "fornow-macos" { errors.append("unexpected scope \(trace.scope)") }
  if trace.undocumentedMarker != "UNVERIFIED" {
    errors.append("UNVERIFIED must be the only undocumented behavior marker")
  }

  let definedEvidence = capturedSet(
    "(?m)^### (AN-[A-Z0-9-]+-[0-9]{3})\\b", in: ledger)
  let definedRequirements = capturedSet(
    "(?m)^#### (FR-[A-Z0-9-]+-[0-9]{3})\\b", in: spec)
  let definedDecisions = capturedSet(
    "(?m)^### (FORNOW-DECISION-[0-9]{3})\\b", in: ledger)
  reportDifference(
    defined: definedEvidence, traced: Set(trace.evidence.keys), kind: "evidence", errors: &errors)
  reportDifference(
    defined: definedRequirements, traced: Set(trace.requirements.keys), kind: "requirement",
    errors: &errors)

  let rows = testRows(in: matrix)
  reportDifference(
    defined: definedRequirements, traced: Set(rows.keys), kind: "test-matrix requirement",
    errors: &errors)

  let allowedConfidence = Set(["A", "B", "C", "R", "A/B"])
  let allowedHosts = Set(["antinote.io", "github.com", "www.digitaltrends.com"])
  for (id, entry) in trace.evidence {
    if entry.title.isEmpty { errors.append("\(id) has an empty title") }
    if !allowedConfidence.contains(entry.confidence) {
      errors.append("\(id) has invalid confidence \(entry.confidence)")
    }
    if entry.sourceDescription.isEmpty { errors.append("\(id) has no source description") }
    if entry.sourceURLs.isEmpty { errors.append("\(id) has no source URL") }
    for source in entry.sourceURLs {
      guard let components = URLComponents(string: source), components.scheme == "https",
        let host = components.host, allowedHosts.contains(host)
      else {
        errors.append("\(id) has invalid or non-evidence URL \(source)")
        continue
      }
    }
    let expectedRequirements = Set(
      trace.requirements.compactMap { requirementID, requirement in
        requirement.evidence.contains(id) ? requirementID : nil
      })
    if Set(entry.requirements) != expectedRequirements {
      errors.append("\(id) requirement inverse mapping does not match requirement sources")
    }
  }

  let allowedClassifications = Set(["parity", "product-decision", "quality"])
  let matrixTestIDs = expandedTestIDs(in: matrix)
  for (id, entry) in trace.requirements {
    if entry.title.isEmpty { errors.append("\(id) has an empty title") }
    if entry.sourceDescription.isEmpty { errors.append("\(id) has no source description") }
    if !allowedClassifications.contains(entry.classification) {
      errors.append("\(id) has invalid classification \(entry.classification)")
    }
    if entry.classification == "parity" && entry.evidence.isEmpty {
      errors.append("\(id) is parity behavior without evidence")
    }
    if entry.classification == "product-decision" && entry.decisions.isEmpty {
      errors.append("\(id) is a product decision without a decision ID")
    }
    if entry.tests.isEmpty { errors.append("\(id) has no tests") }
    for evidenceID in entry.evidence where !definedEvidence.contains(evidenceID) {
      errors.append("\(id) references unknown evidence \(evidenceID)")
    }
    for decisionID in entry.decisions where !definedDecisions.contains(decisionID) {
      errors.append("\(id) references unknown decision \(decisionID)")
    }
    for testID in entry.tests where !matrixTestIDs.contains(testID) {
      errors.append("\(id) references missing test \(testID)")
    }
    if let expectedTests = rows[id], Set(entry.tests) != expectedTests {
      errors.append("\(id) test mapping differs from its test-matrix row")
    }
  }

  let walkthroughRequirements = capturedSet("`(FR-[A-Z0-9-]+-[0-9]{3})`", in: walkthrough)
  let walkthroughDecisions = capturedSet("`(FORNOW-DECISION-[0-9]{3})`", in: walkthrough)
  for id in walkthroughRequirements.subtracting(definedRequirements).sorted() {
    errors.append("manual walkthrough references unknown requirement \(id)")
  }
  for id in walkthroughDecisions.subtracting(definedDecisions).sorted() {
    errors.append("manual walkthrough references unknown decision \(id)")
  }

  let documentedManualURLs = capturedSet(
    "(?m)^Source: (https://antinote\\.io/user-manual\\S*)$", in: walkthrough)
  for (id, entry) in trace.requirements {
    for url in entry.manualURLs where !documentedManualURLs.contains(url) {
      errors.append("\(id) references a manual URL absent from the walkthrough: \(url)")
    }
  }

  if errors.isEmpty {
    let mappedTests = trace.requirements.values.reduce(0) { $0 + $1.tests.count }
    print("macOS traceability validation: PASS")
    print("evidence: \(definedEvidence.count)/\(trace.evidence.count)")
    print("requirements: \(definedRequirements.count)/\(trace.requirements.count)")
    print("mapped test IDs: \(mappedTests)")
    print("defined decisions: \(definedDecisions.count)")
    exit(0)
  }

  FileHandle.standardError.write(Data("macOS traceability validation: FAIL\n".utf8))
  for error in errors.sorted() {
    FileHandle.standardError.write(Data("- \(error)\n".utf8))
  }
  exit(1)
} catch {
  FileHandle.standardError.write(Data("traceability validation could not run: \(error)\n".utf8))
  exit(1)
}
