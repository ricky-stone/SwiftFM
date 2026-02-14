# Changelog

All notable changes to this project are documented in this file.

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
