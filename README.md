# SwiftFM

A tiny, beginner-friendly wrapper for Apple's Foundation Models.

Use it like this:

```swift
let fm = SwiftFM()
let text = try await fm.generateText(for: "Explain a century break in snooker.")
```

That is the core idea: pass a prompt, get a `String`.

## Why SwiftFM

- One-line text generation
- Strongly typed JSON generation with `@Generable`
- Easy prompt + context model input
- Optional model selection per request
- Optional tool calling
- Streaming support

## Requirements

- Xcode 26+
- Swift 6.2+
- iOS 26+, macOS 26+, or visionOS 26+
- Apple Intelligence enabled on a supported device

## Install

In Xcode:

1. `File` -> `Add Package Dependencies...`
2. Use: `https://github.com/ricky-stone/SwiftFM`
3. Choose version `1.0.0` or newer

## Quick Start (String in, String out)

```swift
import SwiftFM

let fm = SwiftFM()

Task {
    do {
        let answer = try await fm.generateText(
            for: "Explain how you think this match might go."
        )
        print(answer)
    } catch {
        print(error.localizedDescription)
    }
}
```

## Pass Your API Model as Context

If your API already returns a Swift model, pass it directly.

```swift
import SwiftFM

struct Match: Codable, Sendable {
    let player: String
    let opponent: String
    let venue: String
    let bestOfFrames: Int
}

let match = Match(
    player: "Judd Trump",
    opponent: "Mark Allen",
    venue: "Alexandra Palace",
    bestOfFrames: 11
)

let fm = SwiftFM()

Task {
    let summary = try await fm.generateText(
        for: "Explain how this match might go in two short sentences.",
        context: match
    )
    print(summary)
}
```

## Choose a Model Per Request

```swift
import SwiftFM

let fm = SwiftFM()

Task {
    let text = try await fm.generateText(
        for: "Give one tactical snooker tip.",
        using: .general
    )
    print(text)
}
```

Available choices:

- `.default`
- `.general`
- `.contentTagging`
- `.custom(SystemLanguageModel)`

## Generate Typed Output (Guided Generation)

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

Task {
    let prediction: MatchPrediction = try await fm.generateJSON(
        for: "Predict a snooker match and return {player,opponent,predictedWinner,confidence}.",
        as: MatchPrediction.self
    )

    print(prediction.predictedWinner)
}
```

You can also do typed output with context:

```swift
let prediction: MatchPrediction = try await fm.generateJSON(
    for: "Predict this specific match using the context JSON.",
    context: match,
    as: MatchPrediction.self
)
```

## Stream Text

```swift
import SwiftFM

let fm = SwiftFM()

Task {
    do {
        for try await snapshot in await fm.streamText(
            for: "Explain snooker safety play in 3 short paragraphs."
        ) {
            print(snapshot)
        }
    } catch {
        print(error)
    }
}
```

## Use Tools (Optional)

```swift
import SwiftFM
import FoundationModels

@Generable
struct PlayerFormArgs: Decodable, Sendable {
    @Guide(description: "Player name")
    let player: String
}

struct PlayerFormTool: Tool {
    let name = "player_form"
    let description = "Returns recent form summary for a player."

    func call(arguments: PlayerFormArgs) async throws -> String {
        "\(arguments.player) has looked steady recently with strong long-potting."
    }
}

let fm = SwiftFM()

Task {
    let text = try await fm.generateText(
        for: "Use the player_form tool for Judd Trump then give one short prediction.",
        request: .init(tools: [PlayerFormTool()])
    )

    print(text)
}
```

## Configure Defaults Once

```swift
import SwiftFM

let fm = SwiftFM(
    config: .init(
        system: "You are a concise snooker analyst.",
        model: .default,
        temperature: 0.4,
        maximumResponseTokens: 300,
        sampling: .greedy
    )
)
```

## Per-Request Overrides

Use `RequestConfig` when you need one-off behavior:

```swift
let text = try await fm.generateText(
    for: "Summarize this match in one sentence.",
    request: .init(
        model: .general,
        temperature: 0.2,
        maximumResponseTokens: 120,
        sampling: .randomTopK(20, seed: 42)
    )
)
```

## Availability Helpers

```swift
if SwiftFM.isModelAvailable {
    print("Ready")
} else {
    print("Not ready: \(SwiftFM.modelAvailability)")
}
```

For specific models:

```swift
let available = SwiftFM.isAvailable(for: .contentTagging)
let state = SwiftFM.availability(for: .contentTagging)
```

## Session Helpers

```swift
await fm.prewarm(promptPrefix: "Snooker analysis")
await fm.resetConversation()
let transcript = await fm.transcript
```

## Error Type

SwiftFM throws `SwiftFM.SwiftFMError` for common cases:

- model unavailable
- context JSON encoding failure
- generation failure
- tool call failure

## License

MIT
