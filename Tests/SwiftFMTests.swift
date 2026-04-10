import Testing
import FoundationModels
@testable import SwiftFM

struct SwiftFMSnookerTests {

    private func isGeneral(_ model: SwiftFM.Model?) -> Bool {
        guard let model else { return false }
        if case .general = model {
            return true
        }
        return false
    }

    private func isContentTagging(_ model: SwiftFM.Model?) -> Bool {
        guard let model else { return false }
        if case .contentTagging = model {
            return true
        }
        return false
    }

    struct MatchContext: Codable, Sendable {
        let player: String
        let opponent: String
        let venue: String
        let bestOfFrames: Int
    }

    @Generable
    struct PracticeDrill: Decodable, Sendable {
        @Guide(description: "Name of the drill")
        let title: String

        @Guide(description: "Short instruction list")
        let steps: String
    }

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

    @Generable
    struct PlayerFormArguments: Decodable, Sendable {
        @Guide(description: "Player name")
        let player: String
    }

    struct PlayerFormTool: Tool {
        let name = "player_form"
        let description = "Returns a short summary of recent snooker form for a player."

        func call(arguments: PlayerFormArguments) async throws -> String {
            "\(arguments.player) has looked steady in recent matches with strong long-potting."
        }
    }

    private func assertNonEmptyOrGuardrail(
        _ makeText: () async throws -> String
    ) async throws {
        do {
            let text = try await makeText()
            #expect(!text.isEmpty)
        } catch let SwiftFM.SwiftFMError.generationFailed(underlying) {
            if let generationError = underlying as? LanguageModelSession.GenerationError,
               case .guardrailViolation(_) = generationError {
                return
            }
            throw SwiftFM.SwiftFMError.generationFailed(underlying)
        }
    }

    private func assertStreamNonEmptyOrGuardrail(
        _ makeStreamText: () async throws -> String
    ) async throws {
        do {
            let text = try await makeStreamText()
            #expect(!text.isEmpty)
        } catch let SwiftFM.SwiftFMError.generationFailed(underlying) {
            if let generationError = underlying as? LanguageModelSession.GenerationError,
               case .guardrailViolation(_) = generationError {
                return
            }
            throw SwiftFM.SwiftFMError.generationFailed(underlying)
        }
    }

    @Test("Availability helper stays consistent")
    func availabilityHelpers() {
        #expect(SwiftFM.isAvailable(for: .default) == SwiftFM.isModelAvailable)
    }

    @Test("PromptSpec renders structured instruction blocks")
    func promptSpecRendering() {
        let spec = SwiftFM.PromptSpec(
            task: "Summarize the upcoming match.",
            rules: ["Use plain text only", "Do not use markdown"],
            outputRequirements: ["Exactly 3 short paragraphs"],
            tone: "Professional and engaging"
        )

        let rendered = spec.render()

        #expect(rendered.contains("Task:\nSummarize the upcoming match."))
        #expect(rendered.contains("Rules:\n1. Use plain text only\n2. Do not use markdown"))
        #expect(rendered.contains("Output Requirements:\n1. Exactly 3 short paragraphs"))
        #expect(rendered.contains("Tone:\nProfessional and engaging"))
    }

    @Test("Fluent builders support a SwiftUI-like beginner style")
    func fluentBuilders() {
        let spec = SwiftFM.prompt("Write a pre-match note.")
            .rule("Use plain text only")
            .rule("Keep it short")
            .requirement("Exactly 2 sentences")
            .tone("Friendly and clear")

        let config = SwiftFM.configuration()
            .system("You are a concise snooker helper.")
            .model(.general)
            .temperature(0.2)
            .maximumResponseTokens(120)
            .contextOptions(
                .init()
                    .heading("Match Payload")
                    .jsonFormatting(.compactSorted)
            )
            .postProcessing(
                .none
                    .trimmingWhitespace()
                    .collapsingSpacesAndTabs()
            )

        let request = SwiftFM.request()
            .model(.contentTagging)
            .tools([PlayerFormTool()])
            .tool(PlayerFormTool())
            .temperature(0.1)
            .maximumResponseTokens(40)
            .includeSchemaInPrompt(false)
            .contextOptions(.init().heading("Compact Payload").jsonFormatting(.compact))
            .postProcessing(.readableParagraphs)

        let rendered = spec.render()

        #expect(rendered.contains("Task:\nWrite a pre-match note."))
        #expect(rendered.contains("1. Use plain text only"))
        #expect(rendered.contains("2. Keep it short"))
        #expect(rendered.contains("Exactly 2 sentences"))
        #expect(rendered.contains("Tone:\nFriendly and clear"))

        #expect(config.system == "You are a concise snooker helper.")
        #expect(isGeneral(config.model))
        #expect(config.temperature == 0.2)
        #expect(config.maximumResponseTokens == 120)
        #expect(config.contextOptions.heading == "Match Payload")
        #expect(config.contextOptions.jsonFormatting == .compactSorted)
        #expect(config.postProcessing.trimWhitespace)
        #expect(config.postProcessing.collapseSpacesAndTabs)

        #expect(isContentTagging(request.model))
        #expect(request.tools?.count == 2)
        #expect(request.temperature == 0.1)
        #expect(request.maximumResponseTokens == 40)
        #expect(request.includeSchemaInPrompt == false)
        #expect(request.contextOptions?.heading == "Compact Payload")
        #expect(request.contextOptions?.jsonFormatting == .compact)
        #expect(request.postProcessing == .readableParagraphs)
    }

    @Test("Text post-processing formats paragraphs and rounds decimals")
    func textPostProcessingFormatting() {
        let postProcessing = SwiftFM.TextPostProcessing(
            trimWhitespace: true,
            collapseSpacesAndTabs: true,
            maximumConsecutiveNewlines: 2,
            roundFloatingPointNumbersTo: 0
        )

        let input = "  Rating 1718.58 vs 1600.49.\n\n\n\nRecent form:\t\tWWD  "
        let output = postProcessing.apply(to: input)

        #expect(output == "Rating 1719 vs 1600.\n\nRecent form: WWD")
    }

    @Test("Public version marker is current")
    func versionMarker() {
        #expect(SwiftFMVersion.current == "2.0.0")
    }

    @Test("Text: prompt only")
    func textPromptOnly() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        try await assertNonEmptyOrGuardrail {
            try await fm.generateText(for: "Define a snooker century break in one sentence.")
        }
    }

    @Test("Text: prompt + context model")
    func textWithContextModel() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        let context = MatchContext(
            player: "Judd Trump",
            opponent: "Mark Allen",
            venue: "Alexandra Palace",
            bestOfFrames: 11
        )

        try await assertNonEmptyOrGuardrail {
            try await fm.generateText(
                for: "Summarize this match context in two short commentator-style sentences.",
                context: context
            )
        }
    }

    @Test("Text: per-request model override")
    func textWithModelOverride() async throws {
        guard SwiftFM.isAvailable(for: .general) else { return }

        let fm = SwiftFM()
        try await assertNonEmptyOrGuardrail {
            try await fm.generateText(
                for: "Give one tactical snooker tip.",
                using: .general
            )
        }
    }

    @Test("Stream: plain text")
    func streamText() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        try await assertStreamNonEmptyOrGuardrail {
            var out = ""
            for try await chunk in await fm.streamText(
                for: "Explain snooker break-building basics in 3 to 4 sentences."
            ) {
                out = chunk
            }
            return out
        }
    }

    @Test("Stream: explicit model helper")
    func streamWithModelHelper() async throws {
        guard SwiftFM.isAvailable(for: .general) else { return }

        let fm = SwiftFM()
        try await assertStreamNonEmptyOrGuardrail {
            var out = ""
            for try await chunk in await fm.streamText(
                for: "Summarize one snooker safety principle in three lines.",
                using: .general
            ) {
                out = chunk
            }
            return out
        }
    }

    @Test("Stream: prompt + context model")
    func streamWithContextModel() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        let context = MatchContext(
            player: "Ronnie O'Sullivan",
            opponent: "Neil Robertson",
            venue: "The Masters",
            bestOfFrames: 11
        )

        try await assertStreamNonEmptyOrGuardrail {
            var out = ""
            for try await chunk in await fm.streamText(
                for: "Explain how this match could unfold in three short paragraphs.",
                context: context
            ) {
                out = chunk
            }
            return out
        }
    }

    @Test("Stream: delta chunks")
    func streamDeltas() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        try await assertStreamNonEmptyOrGuardrail {
            var combined = ""
            for try await delta in await fm.streamTextDeltas(
                for: "Explain one snooker break-building drill in 2 short paragraphs."
            ) {
                combined += delta
            }
            return combined
        }
    }

    @Test("Guided: JSON response")
    func guidedJSON() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        let prediction: MatchPrediction = try await fm.generateJSON(
            for: "Predict a snooker match and return {player,opponent,predictedWinner,confidence}.",
            as: MatchPrediction.self
        )

        #expect(!prediction.player.isEmpty)
        #expect(!prediction.opponent.isEmpty)
        #expect(!prediction.predictedWinner.isEmpty)
        #expect(0.0 ... 1.0 ~= prediction.confidence)
    }

    @Test("Guided: JSON with context")
    func guidedJSONWithContext() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        let context = MatchContext(
            player: "Luca Brecel",
            opponent: "Kyren Wilson",
            venue: "The Crucible",
            bestOfFrames: 19
        )

        let prediction: MatchPrediction = try await fm.generateJSON(
            for: "Predict this specific match using the context JSON.",
            context: context,
            as: MatchPrediction.self
        )

        #expect(!prediction.player.isEmpty)
        #expect(!prediction.opponent.isEmpty)
    }

    @Test("Guided: dynamic schema content")
    func dynamicSchemaContent() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
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
                    description: "Frames in the match",
                    schema: .init(type: Int.self, guides: [.range(1 ... 35)])
                )
            ]
        )

        let content = try await fm.generateContent(
            for: "Generate a short snooker match note with a title and a likely frame count.",
            dynamicSchema: schema
        )

        let title = try content.value(String.self, forProperty: "title")
        let frameCount = try content.value(Int.self, forProperty: "frameCount")

        #expect(!title.isEmpty)
        #expect((1 ... 35).contains(frameCount))
    }

    @Test("Tools: request-scoped tool calling")
    func toolCalling() async throws {
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        try await assertNonEmptyOrGuardrail {
            try await fm.generateText(
                for: "Use the player_form tool for Judd Trump, then give one short neutral summary sentence.",
                request: .init(tools: [PlayerFormTool()])
            )
        }
    }

    @Test("Session helpers: prewarm and reset")
    func sessionHelpers() async throws {
        let fm = SwiftFM(config: .init(system: "You are a concise snooker analyst."))
        await fm.prewarm(promptPrefix: "Snooker strategy")
        await fm.resetConversation()
        let transcript = await fm.transcript
        #expect(transcript.count <= 1)
    }

    @Test("Session helpers: feedback attachment export")
    func feedbackAttachment() async throws {
        let fm = SwiftFM()
        let attachment = await fm.feedbackAttachment(
            sentiment: .positive,
            issues: [.init(category: .unhelpful, explanation: "Needed a more direct answer.")],
            desiredResponseText: "A short direct answer."
        )

        #expect(!attachment.isEmpty)
    }

    @Test("Helpers: token count estimates prompt size")
    func tokenCountHelper() async throws {
        guard #available(macOS 26.4, iOS 26.4, visionOS 26.4, *) else { return }
        guard SwiftFM.isModelAvailable else { return }

        let fm = SwiftFM()
        let count = try await fm.tokenCount(for: "Explain a snooker safety shot in one sentence.")
        #expect(count > 0)
    }
}
