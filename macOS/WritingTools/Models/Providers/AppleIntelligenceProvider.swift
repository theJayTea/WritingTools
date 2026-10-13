import Foundation
import Observation
import FoundationModels

private let logger = AppLogger.logger("AppleIntelligenceProvider")

/// Runs the request on the on-device Apple Intelligence model (FoundationModels).
/// Requires macOS 26+ and Apple Intelligence enabled in System Settings.
@MainActor
@Observable
final class AppleIntelligenceProvider: AIProvider {
    var isProcessing = false
    private var activeTask: Task<Void, any Error>?

    /// Human-readable availability status, or nil when the model is ready to use.
    static var unavailabilityReason: String? {
        guard #available(macOS 26.0, *) else {
            return "Apple Intelligence requires macOS 26 or later."
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac is not eligible for Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off. Enable it in System Settings > Apple Intelligence & Siri."
        case .unavailable(.modelNotReady):
            return "The Apple Intelligence model is still downloading. Try again in a few minutes."
        case .unavailable:
            return "Apple Intelligence is unavailable on this Mac."
        }
    }

    func processText(
        systemPrompt: String? = "You are a helpful writing assistant.",
        userPrompt: String,
        images: [Data] = [],
        streaming: Bool = false
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        guard #available(macOS 26.0, *) else {
            throw Self.error("Apple Intelligence requires macOS 26 or later.")
        }
        if let reason = Self.unavailabilityReason { throw Self.error(reason) }

        let prompt = try await buildPrompt(userPrompt: userPrompt, images: images)
        let session = LanguageModelSession(instructions: systemPrompt ?? "You are a helpful writing assistant.")

        do {
            try Task.checkCancellation()
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            logger.error("Apple Intelligence request failed: \(error.localizedDescription)")
            throw error
        }
    }

    func processTextStreaming(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        onChunk: @escaping @Sendable @MainActor (String) -> Void
    ) async throws {
        isProcessing = true
        defer {
            isProcessing = false
            activeTask = nil
        }

        guard #available(macOS 26.0, *) else {
            throw Self.error("Apple Intelligence requires macOS 26 or later.")
        }
        if let reason = Self.unavailabilityReason { throw Self.error(reason) }

        let prompt = try await buildPrompt(userPrompt: userPrompt, images: images)
        let session = LanguageModelSession(instructions: systemPrompt ?? "You are a helpful writing assistant.")

        let streamTask = Task { @MainActor in
            // Snapshots carry the full text so far; the callback expects only the new part.
            var emitted = ""
            for try await snapshot in session.streamResponse(to: prompt) {
                try Task.checkCancellation()
                let full = snapshot.content
                if full.hasPrefix(emitted) {
                    let delta = String(full.dropFirst(emitted.count))
                    if !delta.isEmpty { onChunk(delta) }
                    emitted = full
                } else {
                    // Model revised earlier text: nothing sensible to append.
                    emitted = full
                }
            }
        }
        activeTask = streamTask

        do {
            try await streamTask.value
        } catch {
            logger.error("Apple Intelligence streaming failed: \(error.localizedDescription)")
            throw error
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
    }

    // The on-device model is text-only, so images go through Apple Vision OCR.
    private func buildPrompt(userPrompt: String, images: [Data]) async throws -> String {
        guard !images.isEmpty else { return userPrompt }
        let ocrText = try await OCRManager.shared.extractText(from: images)
        return ocrText.isEmpty ? userPrompt : userPrompt + "\n\nExtracted Text: \(ocrText)"
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
