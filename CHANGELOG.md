# Changelog

All notable changes to this project are documented in this file.

## 3.0.0 - 2026-05-06

### Added
- Session/context policy:
  - `SessionPolicy.freshPerRequest`
  - `SessionPolicy.reused`
  - `SessionPolicy.manual`
  - `Config.freshSessionPerRequest()`
  - `Config.reusingSession()`
  - `Config.manualSession()`
  - `RequestConfig.freshSession()`
  - `RequestConfig.reusedSession()`
  - `clearSession()`
- Fresh session per request is now the default behavior.
- Guardrail and availability fallback policies:
  - `FallbackPolicy`
  - `FallbackAction`
  - `fallbackText(_:)`
  - `onGuardrailViolation(_:)`
  - `onUnavailableModel(_:)`
  - `retryWithReducedContext()`
  - `retryWithoutOptionalTools()`
- Lightweight structured workflows:
  - `SwiftFM.workflow(generating:)`
  - `SwiftFM.Workflow`
- Generic mixed block responses:
  - `ResponseBlock`
  - `BlockResponse`
  - `BlockResponseBuilder`
  - `SwiftFM.blocks()`
- Tool organization helpers:
  - `ToolGroup`
  - `ToolRegistry`
  - `toolGroup(_:)`
  - `toolRegistry()`
  - config/request tool group builders
  - optional tools for conservative retry behavior
- Debug and testing helpers:
  - `DebugOptions`
  - `DebugEvent`
  - `RequestDiagnostics`
  - `inspectRequest(...)`
  - `debugEvents`
  - `clearDebugEvents()`
  - transcript tool call/output inspection helpers
  - structured output debug descriptions
- Tiny Observable helper for SwiftUI and Observation-based apps:
  - `SwiftFMRunner<Output>`
  - `SwiftFMRunner<String>.runText(...)`

### Changed
- Default context behavior changed from reused session to fresh session per request.
- README rewritten as a beginner-first v3 guide with copyable examples for session policy, fallbacks, workflows, mixed blocks, tool groups, diagnostics, and SwiftUI usage.
- Updated the public source version marker to `3.0.0`.

### Migration
- One-shot apps usually do not need changes.
- Conversation apps should opt into `.reusingSession()` or `.manualSession()`.
- Use `clearSession()` when a reused/manual conversation should start over.

### Tests
- Added coverage for v3 builder APIs, session policy defaults, tool groups, fallback policies, mixed block responses, workflows, request diagnostics, Observable runner state, and fresh-session transcript behavior.

## 2.0.0 - 2026-04-10

### Added
- Beginner-first fluent builder APIs:
  - `SwiftFM.configuration()`
  - `SwiftFM.request()`
  - `SwiftFM.prompt(_:)`
  - chainable modifiers on `Config`, `RequestConfig`, `PromptSpec`, `ContextOptions`, and `TextPostProcessing`
- Runtime structured generation APIs:
  - `generateContent(...)` for `GenerationSchema`
  - `generateContent(...)` for `DynamicGenerationSchema`
  - `streamContent(...)` for schema-driven snapshots
- Structured streaming for typed `@Generable` models:
  - `streamJSON(...)` returning partial generated snapshots
- New Apple Foundation Models helper coverage:
  - `supportedLanguages(for:)`
  - `supports(locale:for:)`
  - `supportsCurrentLocale(for:)`
  - `tokenCount(...)` helpers for prompts, tools, schemas, and transcript entries
  - `feedbackAttachment(...)` export helpers
- Custom adapter helpers on `SwiftFM.Model`:
  - `.adapter(_:)`
  - `.adapter(named:)`
  - `.adapter(fileURL:)`

### Changed
- Improved `SwiftFMError.localizedDescription` for common `LanguageModelSession.GenerationError` cases.
- Updated the public version marker to `2.0.0`.
- Rewrote README around the new fluent SwiftUI-like style while keeping older usage patterns documented.

### Tests
- Added coverage for:
  - fluent builder chains
  - dynamic schema generation
  - feedback attachment export
  - token count helpers
- Test suite now runs 19 tests.

## 1.2.0 - 2026-02-18

### Added
- Structured prompt APIs:
  - `SwiftFM.PromptSpec` for task + rules + output requirements + tone.
  - `generateText(from:)`, `streamText(from:)`, `streamTextDeltas(from:)`.
  - Prompt-spec overloads that also accept `context`.
- Output post-processing APIs:
  - `SwiftFM.TextPostProcessing` for whitespace cleanup, paragraph normalization, and decimal rounding.
  - Config-level defaults and request-level overrides.
- Context embedding controls:
  - `SwiftFM.ContextOptions` with configurable heading and JSON formatting (`prettyPrintedSorted`, `compactSorted`, `compact`).
- Public source version marker:
  - `SwiftFMVersion.current == "1.2.0"`.

### Changed
- `Config` now supports:
  - `contextOptions`
  - `postProcessing`
- `RequestConfig` now supports:
  - `contextOptions`
  - `postProcessing`
- Text generation and streaming now apply optional post-processing before results are returned.
- Context-based generation now uses configurable context embedding options.
- README fully rewritten with beginner-first and power-user sections, plus Swift and SwiftUI examples.

### Tests
- Added tests for:
  - prompt spec rendering
  - text post-processing behavior
  - version marker value

## 1.1.10 - 2026-02-14

### Fixed
- Added a root `LICENSE` file (MIT) so GitHub and badge providers correctly detect project licensing.
- Updated README version references to `1.1.10`.

## 1.1.9 - 2026-02-14

### Changed
- Added README badge row for:
  - Swift version
  - supported platforms
  - latest release
  - license
  - discussions
  - GitHub stars
- Updated README version references to `1.1.9`.

## 1.1.8 - 2026-02-14

### Changed
- Removed playground examples from `Examples/` due unreliable execution UX.
- Removed playground quick-start section from README.
- Updated README version references to `1.1.8`.

## 1.1.7 - 2026-02-14

### Fixed
- Updated `Examples/PromptLab.playground/Contents.swift` to use standard Xcode Playground execution:
  - replaced `#Playground` macro usage
  - now uses `PlaygroundSupport` + `Task` + `needsIndefiniteExecution`
- Updated README quick-run step to say "Press Run in the playground".

## 1.1.6 - 2026-02-14

### Changed
- Replaced `Examples/PromptLab.swift` with a real playground bundle:
  - `Examples/PromptLab.playground/Contents.swift`
  - `Examples/PromptLab.playground/contents.xcplayground`
- Updated README quick-run instructions to open `PromptLab.playground`.
- Added a troubleshooting note for missing play button.
- Updated README version references to `1.1.6`.

## 1.1.5 - 2026-02-14

### Changed
- Added a playground-first onboarding path in README:
  - new "Run in 60 Seconds (Xcode Playground)" section
  - clear quick-run steps
- Added `Examples/PromptLab.swift` with runnable `#Playground` examples for:
  - plain prompt generation
  - prompt + context generation
  - streaming delta output
  - guided typed generation
- Updated README version references to `1.1.5`.

## 1.1.4 - 2026-02-14

### Changed
- Expanded README footer to include:
  - full MIT usage notes
  - Author section
  - Acknowledgments section
  - Version section with current release tag

## 1.1.3 - 2026-02-14

### Changed
- Reworked README structure to a fast-start style similar to SwiftRest:
  - compact snippets first
  - `do/catch` variants for key flows
  - quick sections for advanced users
- Added minimal SwiftUI streaming example (no animation) using `streamTextDeltas`.
- Tightened core examples for beginner readability while keeping fast copy/paste paths.

## 1.1.2 - 2026-02-14

### Changed
- Expanded README with an advanced `.custom(SystemLanguageModel)` guide.
- Added beginner-friendly explanations for `SystemLanguageModel`:
  - `useCase` options (`.general`, `.contentTagging`)
  - `guardrails` options (`.default`, `.permissiveContentTransformations`)
- Added concrete custom-model examples and availability-check snippet.

## 1.1.1 - 2026-02-14

### Changed
- Expanded README session helper docs with beginner-friendly explanations for:
  - `prewarm(promptPrefix:)`
  - `isBusy`
  - `transcript`
  - `resetConversation()`
- Added a practical usage flow for session lifecycle management.

## 1.1.0 - 2026-02-14

### Added
- First-class streaming context APIs:
  - `streamText(for:context:request:)`
  - `streamText(for:context:using:)`
- Streaming convenience APIs:
  - `streamText(for:using:)`
  - `streamTextDeltas(...)` helpers for append-style UI updates.
- New `StreamMode` internally to support snapshot and delta streaming behavior.

### Changed
- Rewrote README with beginner-friendly full explanations for:
  - temperature
  - model selection (`.default`, `.general`, `.contentTagging`)
  - sampling modes (`.automatic`, `.greedy`, `.randomTopK`, `.randomProbability`)
  - content-tagging usage
  - streaming with context examples.
- Expanded tests to cover new streaming APIs.

## 1.0.0 - 2026-02-14

### Added
- Model selection API via `SwiftFM.Model` (`default`, `general`, `contentTagging`, `custom`).
- Per-request overrides with `SwiftFM.RequestConfig`.
- Prompt + `Encodable` context helpers for both text and guided JSON generation.
- Tool-calling support at config level and request level.
- Sampling controls (`automatic`, `greedy`, `randomTopK`, `randomProbability`).
- Session helpers: `prewarm`, `resetConversation`, `transcript`.
- Availability helpers for specific models.
- Expanded Swift Testing coverage for new API paths.

### Changed
- Reworked `SwiftFM` internals to support one-shot model/tool overrides.
- Rewrote README for beginner-first quickstart and copy/paste examples.
- Updated package platforms to Foundation Models supported platforms only: iOS, macOS, visionOS.

### Notes
- This is a major release because it expands and reshapes configuration surface area.
