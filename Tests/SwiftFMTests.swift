import Testing
import FoundationModels
@testable import SwiftFM

struct SwiftFMSnookerTests {

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

    @Test("Availability helper stays consistent")
    func availabilityHelpers() {
        #expect(SwiftFM.isAvailable(for: .default) == SwiftFM.isModelAvailable)
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
        var out = ""

        for try await chunk in await fm.streamText(
            for: "Explain snooker break-building basics in 3 to 4 sentences."
        ) {
            out = chunk
        }

        #expect(!out.isEmpty)
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
}
