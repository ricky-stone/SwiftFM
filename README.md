# SwiftFM

SwiftFM is a very small wrapper around Apple's Foundation Models.

If you are new, the core idea is simple:

```swift
let fm = SwiftFM()
let text = try await fm.generateText(for: "Explain this match in plain English.")
```

You send a prompt, you get a string.

## What You Can Do

- Generate plain text
- Stream text as it is generated
- Pass your own API model as context (`Codable`/`Encodable`)
- Generate typed output with `@Generable`
- Choose model behavior (`.default`, `.general`, `.contentTagging`)
- Use tools to fetch live data during generation
- Tune output with `temperature` and sampling modes

## Requirements

- Xcode 26+
- Swift 6.2+
- iOS 26+, macOS 26+, visionOS 26+
- Apple Intelligence enabled on a supported device

## Install

1. In Xcode, open `File` -> `Add Package Dependencies...`
2. Enter `https://github.com/ricky-stone/SwiftFM`
3. Choose version `1.1.2` or newer

## 1. Quick Start

```swift
import SwiftFM

let fm = SwiftFM()

Task {
    do {
        let answer = try await fm.generateText(
            for: "Explain how this match might go in two short paragraphs."
        )
        print(answer)
    } catch {
        print(error.localizedDescription)
    }
}
```

## 2. Pass Your API Model as Context

If your backend already returns a Swift model, pass it directly.

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

SwiftFM encodes `match` to JSON and injects it into the prompt for you.

## 3. Stream Text

### Full snapshots (replace UI text each update)

```swift
import SwiftFM

let fm = SwiftFM()

Task {
    for try await snapshot in await fm.streamText(
        for: "Explain snooker safety play in 3 short paragraphs."
    ) {
        print(snapshot) // full text so far
    }
}
```

### Stream with context model

```swift
for try await snapshot in await fm.streamText(
    for: "Explain how this specific match might unfold.",
    context: match
) {
    print(snapshot)
}
```

### Delta chunks (append-only UI workflow)

```swift
var text = ""
for try await delta in await fm.streamTextDeltas(
    for: "Give me a tactical preview of this match."
) {
    text += delta
}
```

## 4. Model Types Explained (Simple)

SwiftFM model choices:

- `.default`
: Apple chooses the standard default system model.

- `.general`
: General-purpose language tasks (chat, reasoning, writing, summaries).

- `.contentTagging`
: Better suited to labeling/classifying/tagging text into categories.

- `.custom(SystemLanguageModel)`
: Use your own configured `SystemLanguageModel`.

### Which one should I use?

- Most apps: start with `.default`
- Assistant/chat/explanations: `.general`
- Category labels/tags/intent buckets: `.contentTagging`

### Content tagging example

```swift
import SwiftFM

let fm = SwiftFM()

let tagged = try await fm.generateText(
    for: "Classify this note as one label: billing, support, sales, or bug. Note: App crashes at login.",
    using: .contentTagging
)

print(tagged)
```

### Advanced: `.custom(SystemLanguageModel)` explained

Use `.custom(SystemLanguageModel)` when you need direct control over Apple model configuration.

Most people should still use `.default` first.

#### `useCase` options

- `.general`
: Best for normal assistant work such as answers, explanations, summaries, and reasoning.

- `.contentTagging`
: Best for short label/classification tasks such as intent tagging, category assignment, or content routing.

#### `guardrails` options

- `.default`
: Standard safety and policy behavior. Recommended for most apps.

- `.permissiveContentTransformations`
: More permissive for transformation-style tasks (for example rewriting/translating user-provided content).  
Use this only if you specifically need that behavior.

#### Example: custom model with use case and guardrails

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

#### Example: custom model focused on tagging

```swift
import SwiftFM
import FoundationModels

let taggingModel = SystemLanguageModel(
    useCase: .contentTagging,
    guardrails: .default
)

let fm = SwiftFM(config: .init(model: .custom(taggingModel)))

let label = try await fm.generateText(
    for: "Return one label only: injury-update, transfer-news, or match-result. Text: Late goal secures 2-1 win."
)
print(label)
```

#### Availability check for a custom model

```swift
let custom = SystemLanguageModel(useCase: .general, guardrails: .default)
let isReady = SwiftFM.isAvailable(for: .custom(custom))
```

## 5. Temperature Explained (Very Important)

`temperature` controls randomness.

- Low (`0.0` to `0.3`)
: More stable, more repeatable, less creative.

- Medium (`0.4` to `0.8`)
: Balanced.

- High (`0.9+`)
: More creative/varied, but less consistent.

Good defaults:

- Extraction / classification / strict outputs: `0.0` to `0.3`
- General assistant text: `0.4` to `0.7`
- Creative writing/brainstorming: `0.8`+

Example:

```swift
let fm = SwiftFM(config: .init(temperature: 0.3))
```

## 6. Sampling Modes Explained (`.greedy` and others)

Sampling controls how the next token is chosen.

- `.automatic`
: Let the system decide (good default).

- `.greedy`
: Always picks the highest-probability next token.
  Very deterministic. Great for stable structured behavior.

- `.randomTopK(k, seed:)`
: Randomly chooses from the top `k` most likely next tokens.
  Lower `k` is more focused; higher `k` is more diverse.

- `.randomProbability(threshold, seed:)`
: Randomly chooses from tokens whose cumulative probability is under a threshold (nucleus-style behavior).
  Lower threshold is more conservative; higher threshold is more diverse.

Examples:

```swift
let stable = SwiftFM(config: .init(sampling: .greedy, temperature: 0.1))
let creative = SwiftFM(config: .init(sampling: .randomTopK(40), temperature: 0.9))
let repeatable = SwiftFM(config: .init(sampling: .randomTopK(20, seed: 42), temperature: 0.6))
```

## 7. Per-Request Overrides

You can keep one shared client and override behavior per call.

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

Also works for stream requests:

```swift
for try await snapshot in await fm.streamText(
    for: "Give me a 3 paragraph preview.",
    request: .init(model: .general, temperature: 0.35)
) {
    print(snapshot)
}
```

## 8. Typed Output (Guided Generation)

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

    @Guide(description: "Confidence 0.0 to 1.0")
    let confidence: Double
}

let fm = SwiftFM()

let prediction: MatchPrediction = try await fm.generateJSON(
    for: "Predict a snooker match and return {player,opponent,predictedWinner,confidence}.",
    as: MatchPrediction.self
)
```

## 9. Tool Calling

Use tools when the model needs fresh data (API, database, etc.).

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
        // Call your API and return JSON string
        "{\"id\":\"\(arguments.matchID)\",\"home\":\"A\",\"away\":\"B\"}"
    }
}

let fm = SwiftFM()
let tool = MatchLookupTool()

let response = try await fm.generateText(
    for: "Use match_lookup for id 123 and explain how the match may go.",
    request: .init(tools: [tool])
)
```

## 10. Availability Helpers

```swift
if SwiftFM.isModelAvailable {
    print("Model ready")
} else {
    print("Unavailable: \(SwiftFM.modelAvailability)")
}

let taggingAvailable = SwiftFM.isAvailable(for: .contentTagging)
```

## 11. Session Helpers

```swift
let fm = SwiftFM(config: .init(system: "You are a concise analyst."))

await fm.prewarm(promptPrefix: "Match analysis")
let busy = await fm.isBusy
let transcript = await fm.transcript
await fm.resetConversation()
```

What each one does:

- `prewarm(promptPrefix:)`
: Prepares the model session so the first real response usually starts faster.
  Think of it as warming the engine before you drive.
  Use this before your first important request (for example when a screen opens).

- `isBusy`
: `true` when the session is currently generating a response.
  Use it to disable your send button, avoid duplicate requests, or show a loading state.

- `transcript`
: The in-memory conversation history for this `SwiftFM` instance.
  It includes instructions, prompts, model responses, and tool-call entries.
  Use it for debugging or building chat UIs that inspect prior turns.

- `resetConversation()`
: Clears the current session history and starts a fresh session with the same base config.
  Use this when the user taps "New Chat" or when you want to remove old context.

Simple usage pattern:

```swift
let fm = SwiftFM(config: .init(system: "You are a concise analyst."))

// 1) Warm up once when the view starts
await fm.prewarm(promptPrefix: "Match analysis")

// 2) Before sending, check if another request is still running
guard await !fm.isBusy else { return }

// 3) Send request(s)...
let text = try await fm.generateText(for: "Preview this match in 3 bullets.")

// 4) Inspect conversation if needed
let history = await fm.transcript
print("Transcript entries:", history.count)

// 5) Start fresh when user wants a new thread
await fm.resetConversation()
```

## 12. Errors

SwiftFM throws `SwiftFM.SwiftFMError` for common issues:

- `modelUnavailable`
- `contextEncodingFailed`
- `generationFailed`
- `toolCallFailed`

## License

MIT
