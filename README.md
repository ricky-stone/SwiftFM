# SwiftFM

[![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20%7C%20macOS%2026%2B%20%7C%20visionOS%2026%2B-0A84FF)](https://developer.apple.com/documentation/foundationmodels)
[![Release](https://img.shields.io/github/v/release/ricky-stone/SwiftFM?sort=semver)](https://github.com/ricky-stone/SwiftFM/releases)
[![License](https://img.shields.io/github/license/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/blob/main/LICENSE)
[![Discussions](https://img.shields.io/github/discussions/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/discussions)
[![Stars](https://img.shields.io/github/stars/ricky-stone/SwiftFM?style=social)](https://github.com/ricky-stone/SwiftFM/stargazers)

SwiftFM is a beginner-first Swift wrapper around Apple Foundation Models.

Version `2.0.0` keeps the original power-user features, but makes the package feel much more like SwiftUI:

- modifier-style config chains
- modifier-style request chains
- modifier-style prompt chains
- dynamic schemas and structured streaming
- locale helpers, token counting, and feedback attachment export
- custom adapter helpers

If you already use the older `Config(...)` and `RequestConfig(...)` style, it still works.

## Requirements

- Swift `6.2+`
- Xcode `26+`
- iOS `26+`
- macOS `26+`
- visionOS `26+`
- Apple Intelligence enabled on supported hardware

## Installation

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/ricky-stone/SwiftFM.git", from: "2.0.0")
```

## 30-Second Start

```swift
import SwiftFM

let fm = SwiftFM()
let text = try await fm.generateText(
    for: "Explain a snooker century break in one sentence."
)

print(text)
```

## Beginner Style

This is the new `2.0` feel.

You start from `SwiftFM.configuration()`, `SwiftFM.request()`, or `SwiftFM.prompt(...)`, then chain small modifiers.

```swift
import SwiftFM

let fm = SwiftFM(
    config: SwiftFM.configuration()
        .system("You are clear, friendly, and concise.")
        .model(.general)
        .temperature(0.3)
        .maximumResponseTokens(180)
        .postProcessing(.readableParagraphs)
)

let text = try await fm.generateText(
    for: "Write a short beginner explanation of snooker safety play."
)
```

## One-Off Request Overrides

Use `SwiftFM.request()` when you only want to change one call.

```swift
let text = try await fm.generateText(
    for: "Write a short match preview.",
    request: SwiftFM.request()
        .temperature(0.2)
        .maximumResponseTokens(120)
        .postProcessing(.readableParagraphs)
)
```

## Output Cleanup

`TextPostProcessing` is still here, and now it chains nicely too.

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .postProcessing(
            .none
                .trimmingWhitespace()
                .collapsingSpacesAndTabs()
                .limitingConsecutiveNewlines(to: 2)
                .roundingFloatingPointNumbers(to: 0)
        )
)
```

## Prompt Builder

`PromptSpec` now chains cleanly too.

```swift
let spec = SwiftFM.prompt("Write a pre-match analysis.")
    .rule("Use plain text only")
    .rule("Do not use markdown")
    .requirement("Exactly 3 short paragraphs")
    .tone("Professional and engaging")

let text = try await fm.generateText(from: spec)
print(text)
```

## Context Models

If your app already has Swift models, pass them directly.

```swift
struct MatchVision: Codable, Sendable {
    let home: String
    let away: String
    let venue: String
    let bestOfFrames: Int
}

let vision = MatchVision(
    home: "Judd Trump",
    away: "Mark Allen",
    venue: "Alexandra Palace",
    bestOfFrames: 11
)

let summary = try await fm.generateText(
    for: "Write a short neutral preview using only this data.",
    context: vision,
    request: SwiftFM.request()
        .postProcessing(.readableParagraphs)
)
```

### Context Formatting

You can still control how the JSON is embedded in the prompt.

```swift
let text = try await fm.generateText(
    for: "Summarize this payload for a beginner.",
    context: vision,
    request: SwiftFM.request()
        .contextOptions(
            .init()
                .heading("Match Payload")
                .jsonFormatting(.compactSorted)
        )
)
```

## Text Streaming

SwiftFM still supports both full snapshots and delta chunks.

### Snapshot stream

```swift
for try await snapshot in await fm.streamText(
    for: "Explain snooker break-building in three short paragraphs."
) {
    print(snapshot)
}
```

### Delta stream

```swift
var text = ""

for try await delta in await fm.streamTextDeltas(
    for: "Explain snooker break-building in three short paragraphs."
) {
    text += delta
}
```

## SwiftUI Example

```swift
import SwiftUI
import SwiftFM

struct HomeView: View {
    @State private var text = ""
    @State private var isLoading = true

    private let fm = SwiftFM(
        config: .beginnerFriendly
            .system("You explain things simply.")
            .temperature(0.3)
    )

    var body: some View {
        ZStack {
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            if isLoading {
                ProgressView("Thinking...")
            }
        }
        .task {
            do {
                for try await delta in await fm.streamTextDeltas(
                    from: SwiftFM.prompt("Explain one snooker safety drill.")
                        .requirement("Exactly 2 short paragraphs")
                ) {
                    if isLoading { isLoading = false }
                    text += delta
                }
            } catch {
                isLoading = false
                text = "Error: \(error.localizedDescription)"
            }
        }
    }
}
```

## Typed Output with `@Generable`

```swift
import SwiftFM
import FoundationModels

@Generable
struct MatchPrediction: Decodable, Sendable {
    @Guide(description: "Home player")
    let home: String

    @Guide(description: "Away player")
    let away: String

    @Guide(description: "Predicted winner")
    let winner: String

    @Guide(description: "Confidence from 0.0 to 1.0")
    let confidence: Double
}

let prediction = try await fm.generateJSON(
    for: "Predict this match and return home, away, winner, and confidence.",
    as: MatchPrediction.self
)
```

### Structured Streaming

New in `2.0`: you can stream partial typed snapshots, not just text.

```swift
for try await partial in await fm.streamJSON(
    for: "Generate a snooker match prediction.",
    as: MatchPrediction.self
) {
    print(partial.winner ?? "Waiting...")
}
```

### Apple `26.4` Nil Handling

If you want to use Apple's newer explicit-nil generation behavior, you can do that directly with Foundation Models and still use SwiftFM normally:

```swift
@Generable(representNilExplicitlyInGeneratedContent: true)
struct OptionalNote: Decodable, Sendable {
    let title: String
    let subtitle: String?
}
```

## Dynamic Schemas

New in `2.0`: you can generate runtime-structured content without creating a Swift type first.

```swift
import FoundationModels

let schema = DynamicGenerationSchema(
    name: "SnookerNote",
    properties: [
        .init(
            name: "title",
            description: "Short title",
            schema: .init(type: String.self)
        ),
        .init(
            name: "frameCount",
            description: "Likely number of frames",
            schema: .init(type: Int.self, guides: [.range(1 ... 35)])
        )
    ]
)

let content = try await fm.generateContent(
    for: "Generate a snooker match note with a title and likely frame count.",
    dynamicSchema: schema
)

let title = try content.value(String.self, forProperty: "title")
let frames = try content.value(Int.self, forProperty: "frameCount")
```

### Dynamic Schema Streaming

```swift
for try await snapshot in await fm.streamContent(
    for: "Generate a short structured match note.",
    dynamicSchema: schema
) {
    print(snapshot.jsonString)
}
```

## Tool Calling

Use tools when the model should fetch live data or call app logic.

```swift
import SwiftFM
import FoundationModels

@Generable
struct MatchLookupArgs: Decodable, Sendable {
    @Guide(description: "Match id to fetch")
    let id: String
}

struct MatchLookupTool: Tool {
    let name = "match_lookup"
    let description = "Fetches match JSON by id"

    func call(arguments: MatchLookupArgs) async throws -> String {
        """
        {"id":"\(arguments.id)","home":"Player A","away":"Player B","venue":"Main Arena"}
        """
    }
}

let text = try await fm.generateText(
    for: "Use match_lookup for id 123, then write a short neutral preview.",
    request: SwiftFM.request()
        .tool(MatchLookupTool())
)
```

## Sampling and Temperature

If you want more control, the existing sampling features are still available.

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .model(.general)
        .temperature(0.2)
        .maximumResponseTokens(250)
        .sampling(.greedy)
)
```

## Model Selection

SwiftFM model options:

- `.default`
- `.general`
- `.contentTagging`
- `.custom(SystemLanguageModel)`

```swift
let summary = try await fm.generateText(
    for: "Give one tactical snooker tip.",
    using: .general
)

let label = try await fm.generateText(
    for: "Return one label only: billing, support, bug. Text: app crashes at launch.",
    using: .contentTagging
)
```

## Custom `SystemLanguageModel`

If you want the raw Apple surface, that is still supported too.

```swift
import FoundationModels

let customModel = SystemLanguageModel(
    useCase: .general,
    guardrails: .default
)

let fm = SwiftFM(
    config: SwiftFM.configuration()
        .model(.custom(customModel))
)
```

## Custom Adapters

New in `2.0`: adapter helpers make Apple adapter usage easier to discover.

```swift
let fm = SwiftFM(
    config: .beginnerFriendly
        .model(try .adapter(named: "MyAdapter"))
)
```

You can also load an adapter from disk:

```swift
let model = try SwiftFM.Model.adapter(fileURL: adapterURL)
let fm = SwiftFM(config: .init(model: model))
```

## Availability, Languages, and Locale

```swift
if SwiftFM.isModelAvailable && SwiftFM.supportsCurrentLocale() {
    print("Ready")
} else {
    print("Unavailable: \(SwiftFM.modelAvailability)")
}

let languages = SwiftFM.supportedLanguages(for: .default)
print(languages)
```

## Token Counting (`26.4+`)

Apple added token counting in `26.4`, and SwiftFM now exposes it.

```swift
if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
    let count = try await fm.tokenCount(
        from: SwiftFM.prompt("Explain a snooker safety shot.")
            .requirement("One sentence only")
    )

    print("Prompt tokens:", count)
}
```

There are also static helpers for tools, schemas, and transcript entries:

```swift
if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
    let count = try await SwiftFM.tokenCount(for: schema)
    print(count)
}
```

## Feedback Attachments

Apple recommends exporting feedback attachments when a response is poor or guardrails trigger unexpectedly.

New in `2.0`: you can export that attachment directly from the current session.

```swift
let attachment = await fm.feedbackAttachment(
    sentiment: .negative,
    issues: [
        .init(category: .didNotFollowInstructions, explanation: "It ignored the output format.")
    ],
    desiredResponseText: "A short plain-text answer in exactly two sentences."
)

print("Attachment bytes:", attachment.count)
```

## Session Helpers

```swift
let fm = SwiftFM(
    config: .beginnerFriendly
        .system("You are concise.")
)

await fm.prewarm(promptPrefix: "Match analysis")
let busy = await fm.isBusy
let transcript = await fm.transcript
await fm.resetConversation()
```

What these do:

- `prewarm(promptPrefix:)`: reduce first-response latency
- `isBusy`: `true` while the session is generating
- `transcript`: inspect the current conversation history
- `resetConversation()`: clear the session and start fresh with the same base config

## Error Handling

```swift
do {
    let text = try await fm.generateText(for: "Analyze this match.")
    print(text)
} catch let error as SwiftFM.SwiftFMError {
    print(error.localizedDescription)

    if let generationError = error.generationError {
        print("Foundation Models error:", generationError)
    }
} catch {
    print(error.localizedDescription)
}
```

## Existing APIs Still Work

`2.0.0` adds fluent builder-style usage, but it does not remove the current feature set.

These still work:

- `SwiftFM(config: .init(...))`
- `RequestConfig(...)`
- `PromptSpec(...)`
- `generateText`
- `streamText`
- `streamTextDeltas`
- `generateJSON`
- request-scoped tools
- context embedding options
- post-processing options
- custom `SystemLanguageModel`

## Version

- Current source version: `2.0.0`

## License

SwiftFM is licensed under the MIT License. See `LICENSE`.
