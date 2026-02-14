# SwiftFM

[![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20%7C%20macOS%2026%2B%20%7C%20visionOS%2026%2B-0A84FF)](https://developer.apple.com/documentation/foundationmodels)
[![Release](https://img.shields.io/github/v/release/ricky-stone/SwiftFM?sort=semver)](https://github.com/ricky-stone/SwiftFM/releases)
[![License](https://img.shields.io/github/license/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/blob/main/LICENSE)
[![Discussions](https://img.shields.io/github/discussions/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/discussions)
[![Stars](https://img.shields.io/github/stars/ricky-stone/SwiftFM?style=social)](https://github.com/ricky-stone/SwiftFM/stargazers)

SwiftFM is a Swift 6 wrapper for Apple Foundation Models that keeps text generation simple.

- `SwiftFM` is an `actor`
- Works with plain text, streaming text, tools, and typed guided generation
- Uses on-device Apple Foundation Models

## Requirements

- Swift 6.2+
- Xcode 26+
- iOS 26+
- macOS 26+
- visionOS 26+
- Apple Intelligence enabled on a supported device

## Installation

Use Swift Package Manager with:

- `https://github.com/ricky-stone/SwiftFM.git`

Use `1.1.9` or newer.

## Fast Start

### Compact

```swift
import SwiftFM

let fm = SwiftFM()
let text = try await fm.generateText(for: "Explain this match in plain English.")
print(text)
```

### With `do/catch`

```swift
import SwiftFM

let fm = SwiftFM()

do {
    let text = try await fm.generateText(
        for: "Explain this match in plain English."
    )
    print(text)
} catch {
    print(error.localizedDescription)
}
```

## Prompt + Context Model

If your API already returns a model, pass it directly.

```swift
import SwiftFM

struct MatchVision: Codable, Sendable {
    let home: String
    let away: String
    let homeSeasonRating: Int
    let awaySeasonRating: Int
    let venue: String
}

let vision = MatchVision(
    home: "Judd Trump",
    away: "Mark Allen",
    homeSeasonRating: 1718,
    awaySeasonRating: 1694,
    venue: "Alexandra Palace"
)

let fm = SwiftFM()
let text = try await fm.generateText(
    for: "Write a short pre-match analysis using only the provided data.",
    context: vision
)
print(text)
```

### With `do/catch`

```swift
let fm = SwiftFM()

do {
    let text = try await fm.generateText(
        for: "Write a short pre-match analysis using only the provided data.",
        context: vision
    )
    print(text)
} catch {
    print(error.localizedDescription)
}
```

## Streaming Text

### Snapshot stream (full text each update)

```swift
let fm = SwiftFM()

for try await snapshot in await fm.streamText(
    for: "Explain snooker safety play in 3 short paragraphs."
) {
    print(snapshot)
}
```

### Delta stream (append-only)

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
for try await snapshot in await fm.streamText(
    for: "Write a short match analysis.",
    context: vision
) {
    print(snapshot)
}
```

## Minimal SwiftUI Streaming Example (No Animations)

```swift
import SwiftUI
import SwiftFM

struct HomeView: View {
    @State private var text = ""
    private let fm = SwiftFM()

    var body: some View {
        ScrollView {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .task {
            do {
                for try await delta in await fm.streamTextDeltas(
                    for: "Explain snooker safety play in 3 short paragraphs."
                ) {
                    text += delta
                }
            } catch {
                text = "Error: \(error.localizedDescription)"
            }
        }
    }
}
```

## Guided Typed Output (`@Generable`)

```swift
import SwiftFM
import FoundationModels

@Generable
struct MatchPrediction: Decodable, Sendable {
    @Guide(description: "First player")
    let player: String

    @Guide(description: "Opponent")
    let opponent: String

    @Guide(description: "Predicted winner")
    let predictedWinner: String

    @Guide(description: "Confidence from 0.0 to 1.0")
    let confidence: Double
}

let fm = SwiftFM()
let prediction: MatchPrediction = try await fm.generateJSON(
    for: "Predict a snooker match and return {player,opponent,predictedWinner,confidence}.",
    as: MatchPrediction.self
)
```

### With `do/catch`

```swift
let fm = SwiftFM()

do {
    let prediction: MatchPrediction = try await fm.generateJSON(
        for: "Predict a snooker match and return {player,opponent,predictedWinner,confidence}.",
        as: MatchPrediction.self
    )
    print(prediction.predictedWinner)
} catch {
    print(error.localizedDescription)
}
```

## Model Selection

SwiftFM model options:

- `.default`: Standard default model selection
- `.general`: Best for normal assistant output and explanations
- `.contentTagging`: Best for labeling/classification style tasks
- `.custom(SystemLanguageModel)`: Advanced control

Example:

```swift
let fm = SwiftFM()

let summary = try await fm.generateText(
    for: "Give one tactical snooker tip.",
    using: .general
)

let tag = try await fm.generateText(
    for: "Return one label only: billing, support, bug. Text: app crashes at startup.",
    using: .contentTagging
)
```

## Advanced: Custom SystemLanguageModel

Use this when you need explicit model construction.

```swift
import SwiftFM
import FoundationModels

let custom = SystemLanguageModel(
    useCase: .general,
    guardrails: .default
)

let fm = SwiftFM(config: .init(model: .custom(custom)))
let text = try await fm.generateText(for: "Summarize this match in two lines.")
print(text)
```

`useCase`:
- `.general`: normal assistant tasks
- `.contentTagging`: classification/tagging tasks

`guardrails`:
- `.default`: standard behavior for most apps
- `.permissiveContentTransformations`: more permissive for transformation-style tasks

## Temperature and Sampling (Quick Guide)

`temperature` controls randomness:

- `0.0` to `0.3`: stable and predictable
- `0.4` to `0.8`: balanced
- `0.9+`: more creative, less consistent

Sampling options:

- `.automatic`: system default
- `.greedy`: most deterministic
- `.randomTopK(k, seed:)`: controlled variety
- `.randomProbability(threshold, seed:)`: nucleus-style variety

Example:

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

## Per-Request Overrides

```swift
let fm = SwiftFM()

let text = try await fm.generateText(
    for: "Summarize this match in one sentence.",
    request: .init(
        model: .general,
        temperature: 0.2,
        maximumResponseTokens: 120,
        sampling: .greedy
    )
)
```

Also works for streaming:

```swift
for try await delta in await fm.streamTextDeltas(
    for: "Give a 3 paragraph preview.",
    request: .init(model: .general, temperature: 0.3)
) {
    print(delta, terminator: "")
}
```

## Tool Calling

Use tools when the model needs live data from APIs or databases.

```swift
import SwiftFM
import FoundationModels

@Generable
struct MatchLookupArgs: Decodable, Sendable {
    @Guide(description: "Match ID")
    let matchID: String
}

struct MatchLookupTool: Tool {
    let name = "match_lookup"
    let description = "Fetches match data by id"

    func call(arguments: MatchLookupArgs) async throws -> String {
        // Replace with your API call
        "{\"id\":\"\(arguments.matchID)\",\"home\":\"A\",\"away\":\"B\"}"
    }
}

let fm = SwiftFM()
let tool = MatchLookupTool()

let text = try await fm.generateText(
    for: "Use match_lookup for id 123 and summarize what to expect.",
    request: .init(tools: [tool])
)
print(text)
```

## Availability

```swift
if SwiftFM.isModelAvailable {
    print("Foundation model ready")
} else {
    print("Unavailable: \(SwiftFM.modelAvailability)")
}

let generalReady = SwiftFM.isAvailable(for: .general)
let taggingReady = SwiftFM.isAvailable(for: .contentTagging)
```

## Session Helpers

```swift
let fm = SwiftFM(config: .init(system: "You are a concise analyst."))

await fm.prewarm(promptPrefix: "Match analysis")
let busy = await fm.isBusy
let transcript = await fm.transcript
await fm.resetConversation()
```

What they do:

- `prewarm(promptPrefix:)`: warms the session to reduce first-response latency
- `isBusy`: true while the session is generating
- `transcript`: in-memory history for this session
- `resetConversation()`: clears history and starts a fresh session with same base config

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

Current release tag: `1.1.9`
