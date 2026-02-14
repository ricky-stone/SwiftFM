# Changelog

All notable changes to this project are documented in this file.

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
