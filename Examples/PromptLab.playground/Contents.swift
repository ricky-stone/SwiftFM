import SwiftFM
import FoundationModels
import PlaygroundSupport

struct MatchVision: Codable, Sendable {
    let home: String
    let away: String
    let homeSeasonRating: Int
    let awaySeasonRating: Int
    let venue: String
}

@Generable
struct MatchPrediction: Decodable, Sendable {
    @Guide(description: "Predicted winner")
    let predictedWinner: String

    @Guide(description: "Confidence from 0.0 to 1.0")
    let confidence: Double
}

PlaygroundPage.current.needsIndefiniteExecution = true

Task {
    defer { PlaygroundPage.current.finishExecution() }

    guard SwiftFM.isModelAvailable else {
        print("Foundation model unavailable: \(SwiftFM.modelAvailability)")
        return
    }

    let vision = MatchVision(
        home: "Judd Trump",
        away: "Mark Allen",
        homeSeasonRating: 1718,
        awaySeasonRating: 1694,
        venue: "Alexandra Palace"
    )

    let fm = SwiftFM(
        config: .init(
            system: "You are a concise snooker analyst.",
            model: .general,
            temperature: 0.2,
            maximumResponseTokens: 260,
            sampling: .greedy
        )
    )

    print("\n--- Plain text (prompt only) ---")
    do {
        let plain = try await fm.generateText(
            for: "Explain what a snooker safety shot is in one sentence."
        )
        print(plain)
    } catch {
        print("Plain text failed: \(error.localizedDescription)")
    }

    print("\n--- Plain text (prompt + context model) ---")
    do {
        let contextual = try await fm.generateText(
            for: "Write a short pre-match preview using only the supplied context.",
            context: vision
        )
        print(contextual)
    } catch {
        print("Context generation failed: \(error.localizedDescription)")
    }

    print("\n--- Streaming deltas ---")
    do {
        var streamed = ""
        for try await delta in await fm.streamTextDeltas(
            for: "Write 2 short paragraphs previewing this match.",
            context: vision
        ) {
            streamed += delta
            print(delta, terminator: "")
        }
        print("\n")
        print("Streamed characters: \(streamed.count)")
    } catch {
        print("Streaming failed: \(error.localizedDescription)")
    }

    print("\n--- Guided typed output ---")
    do {
        let prediction: MatchPrediction = try await fm.generateJSON(
            for: "Predict winner and confidence for this match.",
            context: vision,
            as: MatchPrediction.self
        )
        print("Winner: \(prediction.predictedWinner) (\(Int(prediction.confidence * 100))%)")
    } catch {
        print("Guided generation failed: \(error.localizedDescription)")
    }
}
