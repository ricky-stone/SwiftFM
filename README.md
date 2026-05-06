# SwiftFM

[![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20%7C%20macOS%2026%2B%20%7C%20visionOS%2026%2B-0A84FF)](https://developer.apple.com/documentation/foundationmodels)
[![Release](https://img.shields.io/github/v/release/ricky-stone/SwiftFM?sort=semver)](https://github.com/ricky-stone/SwiftFM/releases)
[![License](https://img.shields.io/github/license/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/blob/main/LICENSE)
[![Discussions](https://img.shields.io/github/discussions/ricky-stone/SwiftFM)](https://github.com/ricky-stone/SwiftFM/discussions)
[![Stars](https://img.shields.io/github/stars/ricky-stone/SwiftFM?style=social)](https://github.com/ricky-stone/SwiftFM/stargazers)

SwiftFM is a small Swift package that makes Apple's Foundation Models easier to use.

It gives you friendly Swift APIs for:

- asking the on-device model for text
- getting typed structured output
- calling your own tools
- passing Swift models as context
- choosing how session memory works
- adding simple fallbacks
- using small workflow helpers in real apps
- binding model calls into SwiftUI with a tiny Observable runner

SwiftFM does not replace Foundation Models. It gives you a cleaner front door.

## Requirements

- Swift `6.2+`
- Xcode `26+`
- iOS `26+`
- macOS `26+`
- visionOS `26+`
- Apple Intelligence enabled on supported hardware

## Install

Add SwiftFM with Swift Package Manager:

```swift
.package(url: "https://github.com/ricky-stone/SwiftFM.git", from: "3.0.0")
```

Then import it:

```swift
import SwiftFM
```

If you use `@Generable`, tools, schemas, or guides directly, also import Foundation Models:

```swift
import FoundationModels
```

## The Big v3 Default

SwiftFM `3.0.0` uses a fresh Foundation Models session for each request by default.

That means this:

```swift
let fm = SwiftFM()

let first = try await fm.generateText(for: "Explain safety play.")
let second = try await fm.generateText(for: "Explain break-building.")
```

works like two clean one-shot requests.

The second request does not automatically remember the first request.

This is intentional. Many apps are not chat apps. They ask one question, get one answer, and move on. Fresh sessions help keep context small and predictable.

When you do want a conversation, opt in:

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .reusingSession()
)
```

You can reset that shared session at any time:

```swift
await fm.clearSession()
```

## Smallest Example

```swift
import SwiftFM

let fm = SwiftFM()

let text = try await fm.generateText(
    for: "Explain a snooker century break in one sentence."
)

print(text)
```

That is enough for many apps.

## Builder Style

SwiftFM uses small chainable builders.

Read this like plain English:

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .system("You explain things clearly.")
        .model(.general)
        .temperature(0.3)
        .maximumResponseTokens(180)
        .postProcessing(.readableParagraphs)
)
```

You can also build one request:

```swift
let text = try await fm.generateText(
    for: "Write a short match preview.",
    request: SwiftFM.request()
        .temperature(0.2)
        .maximumResponseTokens(120)
)
```

And you can build prompts:

```swift
let prompt = SwiftFM.prompt("Write a pre-match analysis.")
    .rule("Use plain text only")
    .rule("Do not use markdown")
    .requirement("Exactly 3 short paragraphs")
    .tone("Friendly and professional")

let text = try await fm.generateText(from: prompt)
```

## Session Policy

Session policy controls what happens to conversation context over time.

### One-shot requests

This is the default.

```swift
let fm = SwiftFM()

let answer = try await fm.generateText(
    for: "Summarize this screen for the user."
)
```

Each call gets a clean Foundation Models session.

You can also say it out loud:

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .freshSessionPerRequest()
)
```

### Conversation requests

Use this when each request should remember previous requests.

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .reusingSession()
        .system("You are a helpful tutor.")
)

let first = try await fm.generateText(for: "Teach me one snooker rule.")
let second = try await fm.generateText(for: "Give me a quiz question about that.")
```

Clear the conversation when you are done:

```swift
await fm.clearSession()
```

### Manual session control

Use `manualSession()` when your app wants to be very explicit about when session context is cleared.

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .manualSession()
)

let answer = try await fm.generateText(for: "Start a coaching session.")

await fm.clearSession()
```

## Passing Swift Models As Context

If your app already has data in a Swift struct, pass it directly.

```swift
struct MatchContext: Codable, Sendable {
    let home: String
    let away: String
    let venue: String
    let bestOfFrames: Int
}

let context = MatchContext(
    home: "Judd Trump",
    away: "Mark Allen",
    venue: "Alexandra Palace",
    bestOfFrames: 11
)

let summary = try await fm.generateText(
    for: "Write a short neutral preview using only this data.",
    context: context
)
```

You can control how that context is embedded:

```swift
let summary = try await fm.generateText(
    for: "Summarize this match.",
    context: context,
    request: SwiftFM.request()
        .contextOptions(
            .init()
                .heading("Match Data")
                .jsonFormatting(.compactSorted)
        )
)
```

## Structured Output

Use `@Generable` when you want a Swift type back instead of plain text.

```swift
import SwiftFM
import FoundationModels

@Generable
struct MatchPrediction: Decodable, Sendable {
    @Guide(description: "Predicted winner")
    let winner: String

    @Guide(description: "Confidence from 0.0 to 1.0")
    let confidence: Double

    @Guide(description: "One short reason")
    let reason: String
}

let prediction = try await fm.generateJSON(
    for: "Predict the match winner.",
    context: context,
    as: MatchPrediction.self
)

print(prediction.winner)
```

## Tool Calling

Tools let the model ask your app for information.

```swift
import SwiftFM
import FoundationModels

@Generable
struct PlayerLookupArguments: Decodable, Sendable {
    @Guide(description: "Player name")
    let name: String
}

struct PlayerLookupTool: Tool {
    let name = "player_lookup"
    let description = "Looks up a short player summary."

    func call(arguments: PlayerLookupArguments) async throws -> String {
        "Player summary for \(arguments.name): strong long potting, steady safety."
    }
}

let text = try await fm.generateText(
    for: "Use player_lookup for Judd Trump, then write one sentence.",
    request: SwiftFM.request()
        .tool(PlayerLookupTool())
)
```

## Tool Groups

As apps grow, passing the same tools again and again gets annoying.

Use tool groups:

```swift
let searchTools = SwiftFM.toolGroup("search")
    .tool(PlayerLookupTool())

let fm = SwiftFM(
    config: SwiftFM.configuration()
        .toolGroup(searchTools)
)
```

Or use a registry:

```swift
let registry = SwiftFM.toolRegistry()
    .group(searchTools)
    .group(
        SwiftFM.toolGroup("player-data")
            .tool(PlayerLookupTool())
    )

let text = try await fm.generateText(
    for: "Use the right tool and answer clearly.",
    request: SwiftFM.request()
        .toolRegistry(registry)
)
```

## Optional Tools

Optional tools are normal tools, but SwiftFM can drop them during a fallback retry.

```swift
let text = try await fm.generateText(
    for: "Search if needed, then summarize.",
    request: SwiftFM.request()
        .tool(PlayerLookupTool())
        .optionalTool(PlayerLookupTool())
        .retryWithoutOptionalTools()
)
```

If a tool failure happens, SwiftFM retries once without the optional tools.

## Fallbacks

Foundation Models can fail for normal reasons:

- Apple Intelligence is not ready
- a guardrail was triggered
- the context window is too large
- a tool failed

SwiftFM v3 gives you simple fallback policies.

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .fallbackText("I cannot answer that right now.")
)

let text = try await fm.generateText(
    for: "Write a short answer."
)
```

You can be more specific:

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .onGuardrailViolation(.fallbackText("I cannot help with that request."))
        .onUnavailableModel(.fallbackText("Apple Intelligence is not ready on this device."))
        .retryWithReducedContext()
)
```

Fallbacks are conservative:

- text fallback returns only for text generation
- retries happen at most once
- retry with reduced context means retrying with a fresh session
- retry without optional tools removes only tools you marked optional

## Lightweight Workflows

A workflow is a small convenience layer for one clear app task.

It can define:

- instructions
- tools
- output type
- request settings
- fallback output
- one `run` call

```swift
@Generable
struct SupportReply: Decodable, Sendable {
    @Guide(description: "Short reply to show in the UI")
    let reply: String

    @Guide(description: "Whether the issue needs a human")
    let needsHuman: Bool
}

let workflow = SwiftFM.workflow(generating: SupportReply.self)
    .instructions("Be brief, kind, and practical.")
    .toolGroup(searchTools)
    .request(
        SwiftFM.request()
            .freshSession()
            .temperature(0.2)
    )
    .fallback(
        SupportReply(
            reply: "I cannot answer that right now. Please try again.",
            needsHuman: true
        )
    )

let reply = try await workflow.run(
    "The user cannot find their saved match notes."
)
```

Workflows are optional. You can ignore them and keep using `SwiftFM` directly.

## Mixed Block Responses

Many app UIs need ordered mixed content:

- text
- a reference to an app object
- metadata
- a custom block

SwiftFM v3 includes generic block response types.

```swift
let response = try await fm.generateJSON(
    for: """
    Create an ordered answer with:
    1. a short intro text block
    2. one reference block with id doc-123
    3. one metadata block
    """,
    as: SwiftFM.BlockResponse.self
)

for block in response.blocks {
    switch block.kind {
    case "text":
        print(block.text ?? "")
    case "reference":
        print("Reference:", block.referenceID ?? "")
    case "metadata":
        print(block.metadataJSON ?? "")
    default:
        print(block.name ?? "custom")
    }
}
```

You can also build block responses by hand for tests or fallbacks:

```swift
let fallback = SwiftFM.blocks()
    .text("I cannot load a live answer right now.")
    .reference(id: "help-center", text: "Open help")
    .metadata(name: "source", json: #"{"kind":"fallback"}"#)
    .response()
```

The block types are generic. They are not tied to one app domain.

## Token And Context Diagnostics

Diagnostics are off by default.

Turn them on when you are building or testing:

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .debug(.console)
)
```

With Xcode and OS `26.4+`, you can inspect prompt size before sending a request:

```swift
if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
    let info = try await fm.inspectRequest(
        for: "Explain safety play in one sentence."
    )

    print(info.promptCharacterCount)
    print(info.promptTokenCount ?? 0)
    print(info.contextSize)
}
```

You can also estimate tokens directly:

```swift
if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
    let count = try await fm.tokenCount(
        from: SwiftFM.prompt("Write a short summary.")
            .requirement("One sentence only")
    )

    print(count)
}
```

## Debug And Testing Helpers

SwiftFM keeps debug helpers small and opt-in.

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .debug(
            .init(isEnabled: true, printsToConsole: true, keepsEvents: true)
                .warningNearContextLimit(0.75)
        )
)

let text = try await fm.generateText(for: "Write a short answer.")
let events = await fm.debugEvents
```

You can inspect tool usage from a transcript:

```swift
let transcript = await fm.transcript
let toolNames = SwiftFM.toolCallNames(in: transcript)
```

You can inspect structured output shape:

```swift
let generated = SwiftFM.ResponseBlock.text("Hello").generatedContent
let description = SwiftFM.structuredOutputDescription(generated)
print(description)
```

## SwiftUI Observable Helper

SwiftFM v3 includes a tiny `SwiftFMRunner`.

It tracks:

- loading state
- latest output
- latest error message

It does not force an app architecture.

```swift
import SwiftUI
import SwiftFM

struct SummaryView: View {
    @State private var runner = SwiftFMRunner<String>()

    private let fm = SwiftFM(
        config: SwiftFM.configuration()
            .system("Explain things simply.")
            .freshSessionPerRequest()
    )

    var body: some View {
        VStack(alignment: .leading) {
            if runner.isLoading {
                ProgressView()
            }

            if let output = runner.output {
                Text(output)
            }

            if let error = runner.errorMessage {
                Text(error)
            }

            Button("Generate") {
                Task {
                    await runner.runText(
                        "Explain a snooker safety shot.",
                        using: fm
                    )
                }
            }
        }
        .padding()
    }
}
```

You can use the generic runner for any async operation:

```swift
let runner = SwiftFMRunner<MatchPrediction>()

await runner.run {
    try await fm.generateJSON(
        for: "Predict the match.",
        as: MatchPrediction.self
    )
}
```

## Streaming

Stream full snapshots:

```swift
for try await snapshot in await fm.streamText(
    for: "Explain break-building in three short paragraphs."
) {
    print(snapshot)
}
```

Stream only new text chunks:

```swift
var text = ""

for try await delta in await fm.streamTextDeltas(
    for: "Explain break-building in three short paragraphs."
) {
    text += delta
}
```

Stream structured partial output:

```swift
for try await partial in await fm.streamJSON(
    for: "Predict a match.",
    as: MatchPrediction.self
) {
    print(partial.winner ?? "Waiting...")
}
```

## Dynamic Schemas

Use dynamic schemas when you need a runtime output shape.

```swift
let schema = DynamicGenerationSchema(
    name: "ShortNote",
    properties: [
        .init(
            name: "title",
            description: "Short title",
            schema: .init(type: String.self)
        ),
        .init(
            name: "score",
            description: "Score from 1 to 10",
            schema: .init(type: Int.self, guides: [.range(1 ... 10)])
        )
    ]
)

let content = try await fm.generateContent(
    for: "Create a short note.",
    dynamicSchema: schema
)

let title = try content.value(String.self, forProperty: "title")
```

## Availability

Check whether the model can run:

```swift
if SwiftFM.isModelAvailable {
    print("Ready")
} else {
    print(SwiftFM.modelAvailability)
}
```

Check locale support:

```swift
if SwiftFM.supportsCurrentLocale() {
    print("This locale is supported.")
}
```

## Session Helpers

These helpers apply to the reusable actor session:

```swift
await fm.prewarm(promptPrefix: "Match analysis")
let busy = await fm.isBusy
let transcript = await fm.transcript
await fm.clearSession()
```

Remember: in v3, normal generation uses fresh sessions unless you opt into reuse.

## Error Handling

```swift
do {
    let text = try await fm.generateText(for: "Write a short answer.")
    print(text)
} catch let error as SwiftFM.SwiftFMError {
    print(error.localizedDescription)

    if let generationError = error.generationError {
        print(generationError)
    }
} catch {
    print(error.localizedDescription)
}
```

## Migrating From v2

The main behavior change is session context.

In v2, normal calls reused the actor session more often.

In v3, normal calls use a fresh session per request by default.

If your app is one-shot, you probably do not need to change anything.

If your app is conversational, add `.reusingSession()`:

```swift
let fm = SwiftFM(
    config: SwiftFM.configuration()
        .reusingSession()
)
```

Use `clearSession()` when the conversation should start over.

The old API style still works:

```swift
let fm = SwiftFM(
    config: .init(
        system: "You are concise.",
        model: .general,
        temperature: 0.3
    )
)
```

## Version

- Current source version: `3.0.0`

## License

SwiftFM is licensed under the MIT License. See `LICENSE`.
