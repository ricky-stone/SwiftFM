# SwiftFM

[![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20%7C%20macOS%2026%2B%20%7C%20visionOS%2026%2B-0A84FF)](https://developer.apple.com/documentation/foundationmodels)
[![Release](https://img.shields.io/github/v/release/ricky-stone/SwiftFM?sort=semver)](https://github.com/ricky-stone/SwiftFM/releases)
[![License](https://img.shields.io/github/license/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/blob/main/LICENSE)
[![Discussions](https://img.shields.io/github/discussions/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/discussions)
[![Stars](https://img.shields.io/github/stars/ricky-stone/SwiftFM?style=social)](https://github.com/ricky-stone/SwiftFM/stargazers)

SwiftFM is a simple Swift wrapper around Apple Foundation Models.

It gives you clean APIs for:

- plain text generation
- streaming text (snapshots or deltas)
- typed guided generation with `@Generable`
- model selection (`.default`, `.general`, `.contentTagging`, `.custom`)
- tool calls (live API-backed workflows)
- context models (`Encodable`) without manual JSON string building
- optional output cleanup (paragraph formatting, whitespace cleanup, rating rounding)

## Requirements

- Swift 6.2+
- Xcode 26+
- iOS 26+
- macOS 26+
- visionOS 26+
- Apple Intelligence enabled on supported hardware

## Installation

Use Swift Package Manager with:

- `https://github.com/ricky-stone/SwiftFM.git`

Use release `1.2.0` or newer.

## Quick Start (Swift)

### 1) One line

```swift
import SwiftFM

let fm = SwiftFM()
let text = try await fm.generateText(for: "Explain what break-building means in snooker.")
print(text)
```

### 2) Beginner-safe `do/catch`

```swift
import SwiftFM

let fm = SwiftFM()

do {
    let text = try await fm.generateText(
        for: "Explain what break-building means in snooker."
    )
    print(text)
} catch {
    print("Failed: \(error.localizedDescription)")
}
```

## Pass Your API Model as Context

If your API already returns a model, pass it directly.

```swift
import SwiftFM

struct MatchVision: Codable, Sendable {
    let home: String
    let away: String
    let homeSeasonRating: Double
    let awaySeasonRating: Double
    let venue: String
}

let vision = MatchVision(
    home: "Player A",
    away: "Player B",
    homeSeasonRating: 1718.58,
    awaySeasonRating: 1694.22,
    venue: "Main Arena"
)

let fm = SwiftFM()

do {
    let summary = try await fm.generateText(
        for: "Write a short pre-match analysis using only this data.",
        context: vision
    )
    print(summary)
} catch {
    print(error.localizedDescription)
}
```

## Streaming Text

### Snapshot stream (full text every update)

```swift
let fm = SwiftFM()

for try await snapshot in await fm.streamText(
    for: "Explain snooker safety play in 3 short paragraphs."
) {
    print(snapshot)
}
```

### Delta stream (append only)

```swift
let fm = SwiftFM()
var text = ""

for try await delta in await fm.streamTextDeltas(
    for: "Explain snooker safety play in 3 short paragraphs."
) {
    text += delta
}

print(text)
```

### Stream with context model

```swift
for try await delta in await fm.streamTextDeltas(
    for: "Write a short match preview.",
    context: vision
) {
    print(delta, terminator: "")
}
```

## SwiftUI Examples

### Minimal: auto-generate once (no button)

```swift
import SwiftUI
import SwiftFM

struct HomeView: View {
    @State private var text = "Loading..."
    private let fm = SwiftFM()

    var body: some View {
        ScrollView {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .task {
            do {
                text = try await fm.generateText(
                    for: "Explain how tactical safety works in snooker."
                )
            } catch {
                text = "Error: \(error.localizedDescription)"
            }
        }
    }
}
```

### Minimal streaming with `@State`

```swift
import SwiftUI
import SwiftFM

struct HomeView: View {
    @State private var text = ""
    @State private var isLoading = true

    private let fm = SwiftFM()

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
                    for: "Give a 3 paragraph match preview."
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
    @Guide(description: "Home player name")
    let home: String

    @Guide(description: "Away player name")
    let away: String

    @Guide(description: "Predicted winner")
    let winner: String

    @Guide(description: "Confidence value from 0.0 to 1.0")
    let confidence: Double
}

let fm = SwiftFM()

do {
    let prediction = try await fm.generateJSON(
        for: "Predict this match and return {home,away,winner,confidence}.",
        as: MatchPrediction.self
    )
    print(prediction)
} catch {
    print(error.localizedDescription)
}
```

## Structured Prompts (New)

Use `PromptSpec` when you want better instruction-following.

```swift
let spec = SwiftFM.PromptSpec(
    task: "Write a pre-match analysis from the provided context data.",
    rules: [
        "Use plain text only",
        "Do not use markdown",
        "Mention ratings as whole numbers"
    ],
    outputRequirements: [
        "Exactly 3 short paragraphs",
        "Mention form as wins, losses, draws"
    ],
    tone: "Professional and engaging"
)

let fm = SwiftFM()
let text = try await fm.generateText(from: spec, context: vision)
print(text)
```

You can also stream from a prompt spec:

```swift
for try await delta in await fm.streamTextDeltas(from: spec, context: vision) {
    print(delta, terminator: "")
}
```

## Output Cleanup (New)

`TextPostProcessing` lets you normalize the final text after generation.

Common use cases:

- remove extra whitespace
- keep clean paragraph spacing
- round decimals like `1718.58` to `1719`

```swift
let fm = SwiftFM(
    config: .init(
        postProcessing: .init(
            trimWhitespace: true,
            collapseSpacesAndTabs: true,
            maximumConsecutiveNewlines: 2,
            roundFloatingPointNumbersTo: 0
        )
    )
)

let text = try await fm.generateText(
    for: "Summarize the match data for humans.",
    context: vision
)
```

Per-request override:

```swift
let text = try await fm.generateText(
    for: "Summarize only this payload.",
    context: vision,
    request: .init(
        postProcessing: .readableParagraphs
    )
)
```

## Context Embedding Options (New)

Control how your `context` JSON is injected into the prompt.

```swift
let text = try await fm.generateText(
    for: "Summarize this context.",
    context: vision,
    request: .init(
        contextOptions: .init(
            heading: "Match Payload",
            jsonFormatting: .compactSorted
        )
    )
)
```

`ContextOptions.JSONFormatting`:

- `.prettyPrintedSorted`: easiest to read/debug
- `.compactSorted`: compact JSON but stable key order
- `.compact`: smallest JSON prompt footprint

## Model Selection

SwiftFM model options:

- `.default`: system default model behavior
- `.general`: general writing/assistant tasks
- `.contentTagging`: classification and labeling tasks
- `.custom(SystemLanguageModel)`: full Foundation Models control

```swift
let fm = SwiftFM()

let summary = try await fm.generateText(
    for: "Give one tactical snooker tip.",
    using: .general
)

let label = try await fm.generateText(
    for: "Return one label only: billing, support, bug. Text: app crashes at launch.",
    using: .contentTagging
)
```

## Custom `SystemLanguageModel` (Power Users)

```swift
import SwiftFM
import FoundationModels

let customModel = SystemLanguageModel(
    useCase: .general,
    guardrails: .default
)

let fm = SwiftFM(config: .init(model: .custom(customModel)))
let text = try await fm.generateText(for: "Summarize in 2 lines.")
print(text)
```

`useCase`:

- `.general`: broad assistant and generation tasks
- `.contentTagging`: label/classification focused behavior

`guardrails`:

- `.default`: recommended standard safety behavior
- `.permissiveContentTransformations`: more permissive for transformation-heavy tasks

## Temperature and Sampling

`temperature` controls randomness:

- `0.0` to `0.3`: most predictable
- `0.4` to `0.8`: balanced
- `0.9+`: more creative, less consistent

Sampling options:

- `.automatic`: system default sampling
- `.greedy`: deterministic token choice (most stable)
- `.randomTopK(k, seed:)`: random sample from top-k tokens
- `.randomProbability(threshold, seed:)`: nucleus-style sampling by probability threshold

```swift
let fm = SwiftFM(
    config: .init(
        model: .general,
        temperature: 0.2,
        maximumResponseTokens: 250,
        sampling: .greedy
    )
)
```

## Tool Calling (Live API Flows)

Use tools when the model should fetch live data.

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
        // Replace with your real API call
        """
        {"id":"\(arguments.id)","home":"Player A","away":"Player B","venue":"Main Arena"}
        """
    }
}

let fm = SwiftFM()
let text = try await fm.generateText(
    for: "Use match_lookup for id 123 then write a short neutral preview.",
    request: .init(tools: [MatchLookupTool()])
)

print(text)
```

## Availability and Session Helpers

### Availability

```swift
if SwiftFM.isModelAvailable {
    print("Model ready")
} else {
    print("Unavailable: \(SwiftFM.modelAvailability)")
}
```

### Session lifecycle helpers

```swift
let fm = SwiftFM(config: .init(system: "You are concise."))

await fm.prewarm(promptPrefix: "Match analysis")
let busy = await fm.isBusy
let transcript = await fm.transcript
await fm.resetConversation()
```

What these do:

- `prewarm(promptPrefix:)`: warms the model session to reduce first-response latency
- `isBusy`: `true` while the current session is generating
- `transcript`: current in-memory conversation history
- `resetConversation()`: clears conversation state and starts fresh with same base config

## Error Handling Pattern

```swift
let fm = SwiftFM()

do {
    let text = try await fm.generateText(for: "Analyze this match")
    print(text)
} catch let error as SwiftFM.SwiftFMError {
    print(error.localizedDescription)
} catch {
    print(error.localizedDescription)
}
```

## License

SwiftFM is licensed under the MIT License. See `LICENSE`.

Industry standard for MIT:

- You can use this in commercial/private/open-source projects.
- Keep the copyright + license notice when redistributing.
- Attribution is appreciated but not required by MIT.

## Author

Created and maintained by Ricky Stone.

## Acknowledgments

Thanks to everyone who tests, reports issues, and contributes improvements.

## Version

- Current release tag: `1.2.0`
- Source marker: `SwiftFMVersion.current == "1.2.0"`
