# ForNow AI Policy

## 1. Direct Answer

ForNow 1.0 does **not** need generative AI.

The documented core behavior is implemented with deterministic software:

- text editing: AppKit/TextKit;
- note storage: SQLite;
- math: parser and evaluator;
- unit conversion: Foundation Measurement and reviewed alias data;
- currency conversion: rate provider plus cache;
- search: SQLite FTS;
- OCR: local Apple Vision;
- links and Markdown: parsers;
- timers: state machine and clocks;
- AutoPaste: pasteboard observation;
- export and backup: filesystem and integration adapters.

OCR uses machine-learning technology supplied by Apple, but it is local text
recognition, not a generative model and not an AI chat service.

## 2. Two Separate Questions

### AI used to develop ForNow

Allowed with strict evidence and test controls.

### AI included inside ForNow

Not part of 1.0. It may be added later as an explicit, optional integration or
extension.

These decisions must never be conflated.

## 3. Why Core AI Is Rejected

Generative AI would make core behavior:

- non-deterministic;
- slower;
- dependent on network/provider availability;
- harder to test;
- more expensive;
- risky for temporary private text;
- capable of changing meaning without a precise source edit.

An LLM must not be used for:

- note persistence;
- source-to-decoration mapping;
- calculator parsing or answers;
- unit/currency arithmetic;
- search;
- OCR;
- timer commands;
- link detection;
- paste cleanup;
- expiration;
- backup or restore;
- conflict resolution without a deterministic fallback.

## 4. Evidence-Grounded AI Development

Every AI implementation request must include:

```text
Step:
Evidence IDs:
Requirement IDs:
Test IDs:
Allowed files:
Inputs:
Expected outputs:
Known edge cases:
Explicit non-goals:
Exit criteria:
```

Example:

```text
Implement Step 2.3 Link Shortening.

Evidence:
- AN-TXT-003

Requirements:
- FR-EDIT-004

Tests:
- UT-EDIT-004A through UT-EDIT-004J
- ET-EDIT-004

Do not:
- change Note.body to a shortened URL;
- add unsupported URL schemes;
- shorten inside code mode or fenced code;
- invent behavior for malformed links.

Stop and add an open question if the evidence does not determine behavior.
```

## 5. AI Agent Execution Protocol

For each implementation step, an AI agent must:

1. Read the complete implementation step.
2. Read every referenced `AN-*` evidence entry.
3. Read every referenced `FR-*` requirement.
4. Read all named test cases.
5. Inspect the existing code and local patterns.
6. State any conflict between evidence, requirement, and code.
7. Implement only the selected step.
8. Add tests before claiming completion.
9. Run traceability validation.
10. Run the narrow test suite.
11. Run the required broader suite.
12. Update `docs/progress/STEP-XX.md`.

The agent may not mark a step `DONE` because code compiles. Exit criteria and
tests must pass.

## 6. Hallucination Stop Conditions

The AI must stop implementation and create an open question when:

- no `AN-*` or `FORNOW-DECISION-*` entry supports the requested behavior;
- the manual and changelog conflict without a version decision;
- a shortcut is not documented and conflicts with an existing shortcut;
- math syntax has no defined expected result;
- a unit alias is missing from the versioned fixture;
- copy/paste behavior would destroy source data;
- a window behavior cannot be verified on the current OS;
- a permission or privacy consequence is not specified;
- adding a dependency changes network, licensing, or sandbox behavior;
- a test expectation would need to be guessed.

Open-question format:

```markdown
## OQ-000

- Related step:
- Related evidence:
- Missing fact:
- User impact:
- Options:
- Recommended decision:
- Verification method:
- Owner:
- Deadline:
```

## 7. Source Priority

When sources conflict:

1. Current official user manual for stable behavior.
2. Current official changelog for version-specific behavior.
3. Official extension or press documentation.
4. Direct observation from a named version.
5. ForNow product decision.
6. Third-party reviews only for discovering questions, never as sole parity
   authority.

An AI summary is never an authority.

## 8. Code Review Rules For AI Output

Review must reject:

- source text derived from rendered attributed text;
- database calls from views;
- direct network calls from parsers;
- hidden clipboard polling;
- note content in logs;
- unbounded tasks or timers;
- `@unchecked Sendable` without a written invariant;
- force unwraps around user content;
- regex-only parsing for the math grammar;
- dynamic code execution for calculations;
- hard-coded unit aliases spread across code;
- an AI provider dependency in a core package;
- tests that merely reproduce implementation logic.

## 9. AI-Generated Tests

AI may generate test cases, but expected values must come from:

- the official manual;
- the written ForNow grammar;
- Foundation conversion constants;
- fixed rate fixtures;
- state-machine transition tables;
- independently calculated golden fixtures.

An AI model must not be asked to supply authoritative expected calculator
answers without independent verification.

For math golden data:

1. calculate with Decimal or an independent trusted calculator;
2. record the exact precision policy;
3. review boundary cases;
4. commit the fixture with provenance.

## 10. Dependency And License Checks

AI may recommend a package only after recording:

- canonical repository;
- current stable version;
- license;
- maintenance activity;
- supported platforms and Swift version;
- binary/source dependency status;
- network behavior;
- reason an Apple framework or small internal implementation is insufficient.

Packages must not be added solely because an AI model remembers their name.

## 11. Optional In-Product AI After 1.0

Potential features:

- rewrite selected text;
- summarize selected text or current note;
- translate selected text;
- convert selection to a checklist;
- extract dates or structured fields;
- explain a selected deterministic calculation.

These features must be:

- disabled by default;
- initiated by an explicit command;
- limited to a visible selection or clearly previewed scope;
- sent only after an explicit provider is configured;
- previewed as a diff before replacing source;
- undoable as one source edit;
- cancellable;
- unavailable without breaking the editor;
- clearly marked as provider-generated output.

## 12. Optional AI Architecture

```swift
protocol TextTransformationProvider {
    var providerID: String { get }
    func transform(
        request: TextTransformationRequest
    ) async throws -> TextTransformationResult
}

struct TextTransformationRequest: Sendable {
    let operation: TransformationOperation
    let selectedText: String
    let locale: Locale.Identifier
    let userInstruction: String?
}

struct TextTransformationResult: Sendable {
    let replacementText: String
    let providerMetadata: ProviderMetadata
}
```

Rules:

- only selected text is included by default;
- whole-note scope requires a separate confirmation;
- clipboard history and other notes are never implicitly included;
- API keys live in Keychain;
- requests and responses are not logged;
- provider URLs are allowlisted;
- rate and size limits are enforced;
- output remains plain source text;
- the user approves the replacement preview.

## 13. Local Versus Remote Models

Remote provider:

- higher capability;
- requires network and API key;
- text leaves the device;
- must expose destination and scope before sending.

Local model:

- stronger privacy;
- increased download, memory, and OS requirements;
- variable quality and latency;
- must be optional and separately installed.

ForNow should not bundle a large model in the core application. If local AI is
later supported, it belongs behind the same provider protocol.

## 14. AI Privacy Copy Requirements

Before first remote use, show:

- provider name;
- exact text scope being sent;
- purpose;
- whether the provider may retain data according to its own policy;
- where the API key is stored;
- how to disable and remove the provider.

Do not claim:

- "private";
- "zero retention";
- "not used for training";
- "end-to-end encrypted";

unless the exact provider configuration and current terms have been verified.

## 15. AI Release Gate

An in-product AI feature cannot ship until:

1. Core 1.0 is stable.
2. Provider access is entirely optional.
3. Selection scope is visible.
4. Keychain storage passes security review.
5. Network destination is explicit.
6. Output preview and undo pass.
7. Failure leaves source unchanged.
8. Offline core workflows pass with the provider removed.
9. Privacy copy is reviewed.
10. The feature has its own evidence, requirements, and test IDs.

## 16. Final Decision

- Use AI during development: **yes, under the evidence protocol**.
- Require AI inside ForNow 1.0: **no**.
- Use local Vision OCR: **yes**.
- Add optional text-generation commands later: **possible, post-1.0 and
  opt-in**.

