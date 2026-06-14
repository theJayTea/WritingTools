import Foundation
import AIProxy

@MainActor
protocol AIProvider {

    // Indicates if provider is processing a request
    var isProcessing: Bool { get set }

    // Process text with optional system prompt and images (non-streaming).
    // Streaming is handled exclusively by `processTextStreaming`.
    func processText(systemPrompt: String?, userPrompt: String, images: [Data]) async throws -> String
    
    /// Process text with streaming support - calls onChunk for each token received
    /// Default implementation falls back to non-streaming
    func processTextStreaming(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        onChunk: @escaping @Sendable @MainActor (String) -> Void
    ) async throws

    // Cancel ongoing requests
    func cancel()
}

// Default implementation for providers that don't support streaming
extension AIProvider {
    func processTextStreaming(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        onChunk: @escaping @Sendable @MainActor (String) -> Void
    ) async throws {
        // Default: fall back to non-streaming and deliver result all at once
        let result = try await processText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images
        )
        onChunk(result)
    }
}

// MARK: - Image Format Detection

/// Detects image MIME type from the first bytes of the data.
/// Returns a sensible default ("image/jpeg") when the format is unrecognized.
func detectImageMIMEType(_ data: Data) -> String {
    guard data.count >= 4 else { return "image/jpeg" }
    let header = [UInt8](data.prefix(4))
    if header[0] == 0xFF && header[1] == 0xD8 {
        return "image/jpeg"
    } else if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
        return "image/png"
    } else if header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46 {
        return "image/gif"
    } else if header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 {
        return "image/webp"
    }
    return "image/jpeg"
}

/// Detects the Anthropic `AnthropicImageMediaType` from image data header bytes.
func detectAnthropicMediaType(_ data: Data) -> AnthropicImageMediaType {
    guard data.count >= 4 else { return .jpeg }
    let header = [UInt8](data.prefix(4))
    if header[0] == 0xFF && header[1] == 0xD8 {
        return .jpeg
    } else if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
        return .png
    } else if header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46 {
        return .gif
    } else if header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 {
        return .webp
    }
    return .jpeg
}

// MARK: - Streaming Helpers

/// Awaits a detached streaming `task` while forwarding the calling task's
/// cancellation to it.
///
/// Providers run their SSE byte reading and per-chunk JSON decoding inside a
/// `Task.detached` so that work happens off the main actor (decoding hundreds
/// of chunks on the main thread during a long generation janks the UI). They
/// hop back to the main actor only to deliver each chunk via the `@MainActor`
/// `onChunk` closure. This helper keeps `provider.cancel()` (which cancels the
/// stored task) *and* an upstream task cancellation both able to interrupt the
/// stream promptly.
nonisolated func awaitForwardingCancellation(_ task: Task<Void, any Error>) async throws {
    try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}

// MARK: - Retry Utility for API Calls

/// Errors that should be retried (transient network issues)
enum RetryableError {
    /// Check if an error is retryable (transient network or server issues)
    static func isRetryable(_ error: Error) -> Bool {
        // Check for URL errors that are transient
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        // Check for HTTP 5xx errors only from known API error domains.
        // We must not cast arbitrary errors to NSError and check `.code`,
        // because any Error becomes an NSError and its code may coincidentally
        // fall in the 500-599 range (e.g. file-not-found = 513).
        let nsError = error as NSError
        let apiDomains: Set<String> = [
            "GeminiAPI", "AnthropicAPI", "OpenAIAPI", "MistralAPI",
            "OpenRouterAPI", "OllamaAPI", "CustomProvider"
        ]
        if apiDomains.contains(nsError.domain) {
            return (500...599).contains(nsError.code)
        }

        return false
    }
}

/// Configuration for retry behavior
struct RetryConfig {
    let maxRetries: Int
    let initialDelay: Duration
    let maxDelay: Duration
    let multiplier: Double

    static let `default` = RetryConfig(
        maxRetries: 3,
        initialDelay: .milliseconds(500),
        maxDelay: .seconds(10),
        multiplier: 2.0
    )

    /// No retries - use for providers that handle their own retry logic
    static let none = RetryConfig(
        maxRetries: 0,
        initialDelay: .zero,
        maxDelay: .zero,
        multiplier: 1.0
    )
}

private func durationToNanoseconds(_ duration: Duration) -> Double {
    let components = duration.components
    let secondsInNanoseconds = Double(components.seconds) * 1_000_000_000
    let attosecondsInNanoseconds = Double(components.attoseconds) / 1_000_000_000
    return max(0, secondsInNanoseconds + attosecondsInNanoseconds)
}

private func nanosecondsToDuration(_ nanoseconds: Double) -> Duration {
    .nanoseconds(Int64(max(0, nanoseconds).rounded()))
}

/// Execute an operation with exponential backoff retry
/// - Parameters:
///   - config: Retry configuration
///   - operation: The async operation to retry
/// - Returns: The result of the operation
/// - Throws: The last error if all retries fail
nonisolated func withRetry<T: Sendable>(
    config: RetryConfig = .default,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?
    var currentDelay = config.initialDelay

    for attempt in 0...config.maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error

            // Propagate cancellation immediately — never retry a cancelled task
            if error is CancellationError || Task.isCancelled {
                throw error
            }

            // Don't retry if it's not a retryable error or we've exhausted retries
            if !RetryableError.isRetryable(error) || attempt == config.maxRetries {
                throw error
            }

            // Wait with exponential backoff
            try? await Task.sleep(for: currentDelay)

            // Increase delay for next attempt, capped at maxDelay
            let nextDelayNanos = durationToNanoseconds(currentDelay) * config.multiplier
            let maxDelayNanos = durationToNanoseconds(config.maxDelay)
            currentDelay = nanosecondsToDuration(min(nextDelayNanos, maxDelayNanos))
        }
    }

    throw lastError ?? NSError(domain: "AIProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Retry failed"])
}
