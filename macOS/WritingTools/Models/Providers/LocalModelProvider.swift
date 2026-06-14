import MLX
import MLXVLM
import MLXLLM
import MLXLMCommon
import SwiftUI
import Observation
import Hub
import UniformTypeIdentifiers

private let logger = AppLogger.logger("LocalModelProvider")

// MARK: - Memory Monitoring Helper

/// Logs GPU memory usage for debugging and performance optimization.
/// Uses MLX.GPU.snapshot() to get current memory state.
private func logGPUMemoryUsage(at checkpoint: String) {
    #if DEBUG
    let snapshot = Memory.snapshot()
    let activeMB = Double(snapshot.activeMemory) / (1024 * 1024)
    let cacheMB = Double(snapshot.cacheMemory) / (1024 * 1024)
    let peakMB = Double(snapshot.peakMemory) / (1024 * 1024)
    logger.debug("[\(checkpoint)] GPU Memory - Active: \(activeMB, privacy: .public)MB, Cache: \(cacheMB, privacy: .public)MB, Peak: \(peakMB, privacy: .public)MB")
    #endif
}

// Constants for UserDefaults keys
fileprivate let kModelStatusKey = "local_llm_model_status"
fileprivate let kModelInfoKey = "local_llm_model_info"


@MainActor
@Observable
class LocalModelProvider {

    // Settings are observed manually via withObservationTracking, so ignore here
    @ObservationIgnored
    private let settings = AppSettings.shared

    // UI-facing properties that should trigger view updates
    var isProcessing = false
    var isDownloading = false
    var downloadProgress: Double = 0
    var output = ""
    var modelInfo = ""
    var stat = ""
    var lastError: String?
    var retryCount: Int = 0

    // Internal state - should NOT trigger observation
    @ObservationIgnored
    var downloadTask: Task<Void, Error>?

    // Fix #7: Simple dictionary instead of NSCache to avoid non-deterministic eviction
    @ObservationIgnored
    private var cachedContainer: (key: String, container: ModelContainer)?

    @ObservationIgnored
    var running = false

    // Fix #4/#17: Store generation task for proper cancellation
    @ObservationIgnored
    private var generationTask: Task<Void, Error>?

    @ObservationIgnored
    private var isCancelled = false

    @ObservationIgnored
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    @ObservationIgnored
    private let maxRetries = 3
    
    // Controls whether the model uses its "thinking" mode (if supported).
    var enableThinking: Bool = false
    
    // Platform compatibility check
    static var isAppleSilicon: Bool {
#if arch(arm64)
        return true
#else
        return false
#endif
    }
    
    // Where we keep MLX models
    private static let modelsRoot: URL = {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("WritingTools/MLXModels", isDirectory: true)
    }()
    private static let vlmTempImagePrefix = "writingtools-vlm-"
    private static let staleTempFileMaxAge: TimeInterval = 24 * 60 * 60

    @ObservationIgnored
    private lazy var hub: HubApi = {
        // ensure the folder exists
        try? FileManager.default.createDirectory(at: Self.modelsRoot, withIntermediateDirectories: true)
        return HubApi(downloadBase: Self.modelsRoot)
    }()

    // Is the current platform supported
    var isPlatformSupported: Bool {
        LocalModelProvider.isAppleSilicon
    }
    
    // Computed Property for Selected Configuration
    private var selectedModelConfiguration: ModelConfiguration? {
        LocalModelType.from(id: settings.selectedLocalLLMId)?.configuration
    }
    
    // Computed Property for Selected Model Type
    var selectedModelType: LocalModelType? {
        LocalModelType.from(id: settings.selectedLocalLLMId)
    }
    
    // property to track if we're using a VLM model
    private var isUsingVisionModel: Bool {
        selectedModelType?.isVisionModel ?? false
    }
    
    private func cacheKey(for config: ModelConfiguration) -> String {
        // Use the stable `name` property provided by MLXLMCommon rather than
        // parsing the debug description of `config.id`, which is fragile.
        config.name
    }

    /// Returns the canonical model directory using HubApi's own path resolution.
    /// This ensures download, load, check, and delete all use the same path.
    private func canonicalModelDirectory(for config: ModelConfiguration) -> URL {
        config.modelDirectory(hub: hub)
    }

    // Fix #10/#11: Tuned generation parameters with KV cache quantization for long generations
    private var generationParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            kvBits: 8,
            kvGroupSize: 64,
            quantizedKVStart: 512,
            temperature: 0.6
        )
    }
    let maxTokens = 10000
    
    enum LoadState: Equatable {
        case idle
        case checking
        case needsDownload
        case downloaded
        case loading
        case loaded(ModelContainer)
        case error(String)
        
        static func == (lhs: LocalModelProvider.LoadState, rhs: LocalModelProvider.LoadState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.checking, .checking): return true
            case (.needsDownload, .needsDownload): return true
            case (.downloaded, .downloaded): return true
            case (.loading, .loading): return true
            case (.loaded(let c1), .loaded(let c2)): return c1 === c2
            case (.error(let s1), .error(let s2)): return s1 == s2
            default: return false
            }
        }
    }
    
    var loadState = LoadState.idle
    
    // Model Directory Calculation - uses canonical HubApi path
    private var modelDirectory: URL? {
         guard let config = selectedModelConfiguration else { return nil }
         return canonicalModelDirectory(for: config)
     }
    
    init() {
        if isPlatformSupported {
            // Fix #9: 512MB GPU cache for 3-4B models on Apple Silicon unified memory
            MLX.Memory.cacheLimit = 512 * 1024 * 1024

            // Fix #14: Seed once at init instead of every request
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            observeSettings()
            startMemoryPressureMonitoring()
            Task { await checkModelStatus() }

        } else {
            modelInfo = "Local LLM is only available on Apple Silicon devices"
            loadState = .error("Platform not supported")
        }

        // Sweep stale VLM temp image files left by previous sessions
        // (e.g. after a crash or force-quit before the defer cleanup ran).
        Self.cleanupStaleTempFiles()
    }

    /// Removes leftover VLM temp image files from the system temp directory.
    /// Only removes app-owned files with the expected prefix and UUID suffix.
    private static func cleanupStaleTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        let extensions: Set<String> = ["png", "jpg", "tiff"]
        let now = Date()
        guard let contents = try? fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        for url in contents {
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            // Only remove files that follow our ownership prefix + UUID contract.
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.hasPrefix(vlmTempImagePrefix) else { continue }
            let uuidPortion = String(stem.dropFirst(vlmTempImagePrefix.count))
            guard UUID(uuidString: uuidPortion) != nil else { continue }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let creationDate = values?.creationDate ?? values?.contentModificationDate ?? now
            guard now.timeIntervalSince(creationDate) >= staleTempFileMaxAge else { continue }
            try? fm.removeItem(at: url)
        }
    }

    private static func makeManagedTempImageURL(pathExtension: String) -> URL {
        let fileName = vlmTempImagePrefix + UUID().uuidString + "." + pathExtension
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.selectedLocalLLMId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                // When the selection changes, reset state and check the new model.
                self?.resetModelState()
                await self?.checkModelStatus()
                self?.observeSettings()
            }
        }
    }
    
    // Reset state when model selection changes
    private func resetModelState() {
        cancelDownload()
        cancel()

        // Releasing the previously-loaded model so switching between local
        // models doesn't accumulate multiple multi-GB containers in memory.
        releaseLoadedModelMemory()

        loadState = .idle
        modelInfo = ""
        lastError = nil
        retryCount = 0
        output = ""
        stat = ""
        isDownloading = false
        downloadProgress = 0
        isCancelled = false
    }
    
    // Fix #6: Added skipIfError parameter to prevent overwriting error state after load failure
    private func checkModelStatus(skipIfError: Bool = false) async {
        guard isPlatformSupported else {
            modelInfo = "Local LLM is only available on Apple Silicon devices"
            loadState = .error("Platform not supported")
            return
        }
        guard let modelDir = modelDirectory, let modelType = selectedModelType else {
            modelInfo = "No local model selected."
            loadState = .idle
            return
        }
        
        guard !isDownloading, loadState != .loading else {
            logger.debug("checkModelStatus: Skipping check, currently downloading or loading.")
            return
        }

        // Don't overwrite an error state that was just set by load()
        if skipIfError, case .error = loadState {
            logger.debug("checkModelStatus: Skipping check, preserving current error state.")
            return
        }
        
        
        loadState = .checking
        modelInfo = "Checking status for \(modelType.displayName)..."

        // Perform file I/O off the main actor to avoid blocking the UI.
        let dirURL = modelDir
        let result: (exists: Bool, isDir: Bool, isEmpty: Bool, error: NSError?) = await Task.detached(priority: .userInitiated) {
            let fileCoordinator = NSFileCoordinator()
            var fileError: NSError?
            var exists = false
            var isDirectory: ObjCBool = false
            var isEmpty = true

            fileCoordinator.coordinate(readingItemAt: dirURL, options: .withoutChanges, error: &fileError) { url in
                exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if exists && isDirectory.boolValue {
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                        isEmpty = contents.isEmpty
                    } catch {
                        logger.error("Error reading directory contents: \(error.localizedDescription)")
                        isEmpty = true
                    }
                }
            }
            return (exists, isDirectory.boolValue, isEmpty, fileError)
        }.value

        if let fileError = result.error {
            loadState = .error("Error checking model directory: \(fileError.localizedDescription)")
            modelInfo = "Error checking \(modelType.displayName)."
            lastError = fileError.localizedDescription
        } else if result.exists && result.isDir && !result.isEmpty {
            loadState = .downloaded
            modelInfo = "\(modelType.displayName) is downloaded."
        } else {
            if result.exists && result.isDir && result.isEmpty {
                // Attempt to remove empty directory
                try? FileManager.default.removeItem(at: modelDir)
                logger.debug("checkModelStatus: Removed empty directory at \(modelDir.path)")
            }
            loadState = .needsDownload
            modelInfo = "\(modelType.displayName) needs to be downloaded."
        }
        // Clear lastError if status check was successful
        if loadState == .downloaded || loadState == .needsDownload {
            lastError = nil
        }
    }

    private func canStartDownload(from state: LoadState) -> Bool {
        switch state {
        case .needsDownload, .idle, .checking, .error(_):
            return true
        default:
            return false
        }
    }
    
    func startDownload() {
        guard isPlatformSupported else {
            lastError = "Local LLM is only available on Apple Silicon devices"
            return
        }
        guard selectedModelConfiguration != nil else {
            lastError = "No model selected to download."
            return
        }
        // Prevent starting if already downloading or task exists
        guard !isDownloading, downloadTask == nil else {
            logger.info("startDownload: Download already in progress or task exists.")
            return
        }
        // Prevent starting if already downloaded/loading/loaded
        guard canStartDownload(from: loadState) else {
            logger.warning("startDownload: Cannot start download from state \(String(describing: self.loadState)).")
            // Update info based on state
            switch loadState {
            case .downloaded, .loaded: modelInfo = "\(selectedModelType?.displayName ?? "Model") is already available."
            case .loading: modelInfo = "\(selectedModelType?.displayName ?? "Model") is loading."
            default: break
            }
            return
        }
        
        
        logger.debug("startDownload: Proceeding to initiate download for \(self.selectedModelType?.displayName ?? "Unknown").")
        
        isCancelled = false
        retryCount = 0
        lastError = nil
        isDownloading = true
        downloadProgress = 0
        modelInfo = "Starting download for \(selectedModelType?.displayName ?? "model")..."
        loadState = .needsDownload
        
        // Fix #5: Task<Void, Error> since the result is stored in loadState/cache, not read from task
        downloadTask = Task {
            logger.debug("startDownload: Task created, calling load()")
            do {
                let _ = try await load()
                logger.debug("startDownload: Task finished successfully.")
            } catch {
                logger.error("startDownload: Task finished with error: \(error.localizedDescription)")
                throw error
            }
        }
        logger.debug("startDownload: downloadTask assigned.")
    }
    
    // cancelDownload
    func cancelDownload() {
        guard isPlatformSupported else { return }
        
        // Only proceed if a download is actually in progress
        guard isDownloading, let task = downloadTask else {
            logger.info("cancelDownload: No active download task to cancel.")
            isDownloading = false
            downloadTask = nil
            isCancelled = false
            return
        }
        
        logger.debug("cancelDownload: Initiating cancellation...")
        
        isCancelled = true
        task.cancel()
        downloadTask = nil
        
        // Immediate UI Update
        isDownloading = false
        downloadProgress = 0 // Reset progress visually
        modelInfo = "Cancelling download..." // Update status immediately
        lastError = nil // Clear any previous error message
    }
    
    func retryDownload() {
        guard isPlatformSupported else {
            lastError = "Local LLM is only available on Apple Silicon devices"
            return
        }
        guard selectedModelConfiguration != nil else {
            lastError = "No model selected to retry download."
            return
        }
        guard retryCount < maxRetries else {
            lastError = "Maximum retry attempts reached for \(selectedModelType?.displayName ?? "model")."
            modelInfo = lastError ?? ""
            loadState = .error(lastError ?? "Max retries reached")
            return
        }
        guard !isDownloading, downloadTask == nil else {
            logger.warning("retryDownload: Cannot retry while another download is active.")
            modelInfo = "Cannot retry: another download is active."
            return
        }
        
        retryCount += 1
        loadState = .needsDownload
        lastError = nil
        modelInfo = "Retrying download (\(retryCount)/\(maxRetries)) for \(selectedModelType?.displayName ?? "model")..."
        logger.debug("retryDownload: Attempting retry \(self.retryCount)/\(self.maxRetries)")
        startDownload()
    }
    
    func revealModelsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.modelsRoot])
    }

    func cleanLegacyCacheForSelectedModel() {
        // Remove any old cached copy (previous defaultHubApi downloads stored in ~/Library/Caches)
        guard let config = selectedModelConfiguration else { return }
        let modelName = config.name
        let caches =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches", isDirectory: true)
        // Extract the repo name portion (after the slash in "org/repo")
        let repoName = modelName.split(separator: "/").last.map(String.init) ?? ""
        guard !repoName.isEmpty else { return }
        if let contents = try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.localizedCaseInsensitiveContains(repoName) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    
    func deleteModel() async throws {
        guard isPlatformSupported else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Platform not supported"])
        }
        guard let modelDir = modelDirectory, let modelType = selectedModelType else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected to delete."])
        }
        let key = cacheKey(for: modelType.configuration)
        guard !isDownloading && !running && loadState != .loading else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot delete while model is busy (downloading, running, or loading)"])
        }
        
        if case .loaded = loadState {
            loadState = .downloaded
        }
        
        // Perform the potentially multi-GB file deletion off the main thread
        let dirPath = modelDir.path
        let displayName = modelType.displayName
        do {
            try await Task.detached(priority: .utility) {
                let fm = FileManager.default
                var isDirectory: ObjCBool = false
                let exists = fm.fileExists(atPath: dirPath, isDirectory: &isDirectory)
                
                if exists {
                    try fm.removeItem(atPath: dirPath)
                }
            }.value
            
            logger.debug("Model directory deleted: \(dirPath)")
            
            // Reset state *after* successful deletion (back on MainActor)
            resetModelState()
            if cachedContainer?.key == key {
                cachedContainer = nil
            }
            Task { await checkModelStatus() }
            modelInfo = "\(displayName) deleted."
            
        } catch {
            logger.error("Failed to delete model \(displayName): \(error.localizedDescription)")
            let message = "Failed to delete \(displayName): \(error.localizedDescription)"
            lastError = message
            modelInfo = message
            loadState = .error(message)
            throw error
        }
    }
    
    func load() async throws -> ModelContainer {
        guard isPlatformSupported else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Platform not supported"])
        }
        guard let config = selectedModelConfiguration, let modelType = selectedModelType else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected to load."])
        }
        let key = cacheKey(for: config)
        
        logger.debug("load: Function called. Current state: \(String(describing: self.loadState))")

        // Fix #7: Check simple dictionary cache
        if let cached = cachedContainer, cached.key == key {
            loadState = .loaded(cached.container)
            modelInfo = "\(modelType.displayName) is ready (cached)."
            return cached.container
        }

        if case .loaded(let container) = loadState {
            logger.debug("load: Model already loaded.")
            cachedContainer = (key: key, container: container)
            return container
        }
        if case .loading = loadState {
            logger.debug("load: Model is already loading (called directly?).")
            throw NSError(domain: "LocalLLM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Model is already loading."])
        }
        
        // --- Download Block ---
        if case .needsDownload = loadState {
            logger.debug("load: State is .needsDownload. Preparing to download \(modelType.displayName).")
            isDownloading = true
            
            do {
                // Select the appropriate factory based on whether it's a vision model
                let factory: ModelFactory = modelType.isVisionModel
                ? VLMModelFactory.shared
                : LLMModelFactory.shared
                
                logger.debug("load: Calling \(modelType.isVisionModel ? "VLM" : "LLM")ModelFactory.shared.loadContainer for \(String(describing: config.id))")
                
                let modelContainer = try await factory.loadContainer(
                    hub: hub,
                    configuration: config
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        // Check isCancelled flag AND ensure we are still meant to be downloading
                        guard !self.isCancelled, self.isDownloading else { return }
                        self.downloadProgress = progress.fractionCompleted
                        // Only update info if still downloading (might have been set to "Cancelling..." by cancelDownload)
                        if self.isDownloading {
                            self.modelInfo = "Downloading \(modelType.displayName): \(Int(progress.fractionCompleted * 100))%"
                        }
                    }
                }
                // --- Download Success ---
                logger.debug("load: loadContainer completed successfully for download.")
                isDownloading = false
                downloadProgress = 1.0
                downloadTask = nil // Clear task reference
                let numParams = await modelContainer.perform { context in context.model.numParameters() }
                modelInfo = "\(modelType.displayName) loaded. Weights: \(numParams / (1024 * 1024))M"
                cachedContainer = (key: key, container: modelContainer)
                loadState = .loaded(modelContainer)
                logger.debug("load: State set to .loaded")
                return modelContainer
                
            } catch { // Catch ALL errors here
                // --- Download Error/Cancellation ---
                logger.error("load: Error during loadContainer (download): \(error.localizedDescription), isCancelled flag: \(self.isCancelled)")
                
                // Determine if it was a user cancellation
                let wasExplicitlyCancelled = isCancelled // Check our flag first
                let isCancellationError = error is CancellationError || (error as NSError).code == NSUserCancelledError
                
                // --- Important: Reset flags *before* updating state/checking status ---
                isDownloading = false
                downloadProgress = 0
                downloadTask = nil // Clear task reference
                
                if wasExplicitlyCancelled || isCancellationError {
                    logger.debug("load: Download cancelled.")
                    let message = "Download cancelled."
                    lastError = message
                    modelInfo = message
                    // State should revert correctly after checkModelStatus
                } else {
                    // Handle other errors (network, disk space, etc.)
                    let nsError = error as NSError
                    let message = nsError.domain == NSURLErrorDomain
                    ? "Network error downloading \(modelType.displayName): \(nsError.localizedDescription)"
                    : "Error downloading \(modelType.displayName): \(nsError.localizedDescription)"
                    lastError = message
                    modelInfo = message
                    loadState = .error(message) // Set error state immediately
                    logger.error("load: State set to .error")
                }
                
                // Fix #6: Use skipIfError to prevent overwriting the error state we just set
                await checkModelStatus(skipIfError: true)
                
                // Re-throw the original error or a CancellationError
                if wasExplicitlyCancelled || isCancellationError {
                    throw CancellationError()
                } else {
                    throw error
                }
            }
            // --- Load from Disk Block ---
        } else if case .downloaded = loadState {
            logger.debug("load: State is .downloaded. Loading \(modelType.displayName) from disk.")
            loadState = .loading
            modelInfo = "Loading \(modelType.displayName)..."
            do {
                let factory: ModelFactory = modelType.isVisionModel
                ? VLMModelFactory.shared
                : LLMModelFactory.shared
                
                logger.debug("load: Calling \(modelType.isVisionModel ? "VLM" : "LLM")ModelFactory.shared.loadContainer for \(String(describing: config.id))")
                let modelContainer = try await factory.loadContainer(hub: hub, configuration: config)
                logger.debug("load: loadContainer completed successfully (from disk).")
                logGPUMemoryUsage(at: "Model Loaded")
                let numParams = await modelContainer.perform { context in context.model.numParameters() }
                modelInfo = "\(modelType.displayName) loaded. Weights: \(numParams / (1024 * 1024))M"
                cachedContainer = (key: key, container: modelContainer)
                loadState = .loaded(modelContainer)
                logger.debug("load: State set to .loaded")
                return modelContainer
            } catch let error as NSError {
                logger.error("load: Error during loadContainer (from disk): \(error.localizedDescription)")
                let message = "Error loading \(modelType.displayName): \(error.localizedDescription)"
                lastError = message
                modelInfo = message
                loadState = .error(message)
                logger.error("load: State set to .error")
                throw error
            }
            // --- Other States ---
        } else {
            logger.warning("load: Cannot load model from current state: \(String(describing: self.loadState))")
            throw NSError(domain: "LocalLLM", code: -5, userInfo: [NSLocalizedDescriptionKey: "Cannot load model from current state: \(loadState)"])
        }
    }
    
    // Fix #2/#3/#13: Synchronous state reset, no busy-wait, guard against concurrent generation
    func processText(systemPrompt: String?, userPrompt: String, images: [Data]) async throws -> String {
        guard isPlatformSupported else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Platform not supported"])
        }
        guard selectedModelConfiguration != nil else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected for processing."])
        }
        
        // Fix #3: Reject concurrent generation instead of busy-waiting
        guard !running else {
            throw NSError(domain: "LocalLLM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Generation already in progress."])
        }
        
        running = true
        isProcessing = true
        isCancelled = false
        output = ""
        
        // Fix #2: Synchronous state reset in defer (we're already on @MainActor)
        defer {
            running = false
            isProcessing = false
            generationTask = nil
        }
        
        // Load the model (uses cache if already loaded)
        let modelContainer = try await load()
        
        // Wrap generation in a Task so cancel() can cancel it cooperatively.
        // Using Task<Void, Error> so thrown errors (including CancellationError)
        // propagate correctly through `try await task.value`.
        var generationResult = ""
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            if isUsingVisionModel && !images.isEmpty {
                generationResult = try await processWithVLM(
                    modelContainer: modelContainer,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    images: images,
                    streaming: false
                )
            } else {
                var combinedPrompt = userPrompt
                if !images.isEmpty && !isUsingVisionModel {
                    let ocrText = try await OCRManager.shared.extractText(from: images)
                    if !ocrText.isEmpty {
                        combinedPrompt += "\n\n[Extracted Text from Image(s)]:\n\(ocrText)"
                    }
                }
                
                generationResult = try await processWithLLM(
                    modelContainer: modelContainer,
                    systemPrompt: systemPrompt,
                    userPrompt: combinedPrompt,
                    streaming: false
                )
            }
        }
        generationTask = task
        
        do {
            try await task.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Error during text generation: \(error.localizedDescription)")
            lastError = "Generation failed: \(error.localizedDescription)"
            stat = "Error"
            throw error
        }
        
        if isCancelled || Task.isCancelled {
            throw CancellationError()
        }

        if generationResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let error = NSError(
                domain: "LocalLLM",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Generation produced no output."]
            )
            logger.error("Generation completed without output")
            lastError = "Generation produced no output."
            stat = "Error"
            throw error
        }
        return generationResult
    }
    
    // Fix #1/#16: Real streaming implementation that calls onChunk per token batch
    func processTextStreaming(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        onChunk: @escaping @Sendable @MainActor (String) -> Void
    ) async throws {
        guard isPlatformSupported else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Platform not supported"])
        }
        guard selectedModelConfiguration != nil else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected for processing."])
        }
        
        guard !running else {
            throw NSError(domain: "LocalLLM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Generation already in progress."])
        }
        
        running = true
        isProcessing = true
        isCancelled = false
        output = ""
        
        defer {
            running = false
            isProcessing = false
            generationTask = nil
        }
        
        let modelContainer = try await load()
        
        // Build UserInput based on model type
        let userInput: UserInput
        var vlmTempURLs: [URL] = []
        if isUsingVisionModel && !images.isEmpty {
            let result = try buildVLMInput(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)
            userInput = result.input
            vlmTempURLs = result.tempURLs
        } else {
            var combinedPrompt = userPrompt
            if !images.isEmpty && !isUsingVisionModel {
                let ocrText = try await OCRManager.shared.extractText(from: images)
                if !ocrText.isEmpty {
                    combinedPrompt += "\n\n[Extracted Text from Image(s)]:\n\(ocrText)"
                }
            }
            userInput = buildLLMInput(systemPrompt: systemPrompt, userPrompt: combinedPrompt)
        }
        
        // Clean up VLM temp files after generation completes or fails
        defer {
            for url in vlmTempURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        // Wrap generation in a Task so cancel() can cancel it cooperatively.
        // Using Task<Void, Error> so thrown errors propagate correctly.
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await generateResponseStreaming(
                userInput: userInput,
                modelContainer: modelContainer,
                onChunk: onChunk
            )
        }
        generationTask = task
        
        do {
            try await task.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Streaming generation error: \(error.localizedDescription)")
            lastError = "Generation failed: \(error.localizedDescription)"
            throw error
        }
        
        if isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// Stores generation result to pass out of perform block
    private struct GenerationResult: Sendable {
        let text: String
        let tokensPerSecond: Double
        let timeToFirstToken: TimeInterval
    }

    // Fix #15: Use ModelContainer.generate() convenience method
    private func generateResponse(
        userInput: UserInput,
        modelContainer: ModelContainer,
        streaming: Bool
    ) async throws -> String {
        logGPUMemoryUsage(at: "Generation Start")
        let parameters = generationParameters
        let start = Date()

        let input = try await modelContainer.prepare(input: userInput)
        let stream = try await modelContainer.generate(input: input, parameters: parameters)

        var fullOutput = ""
        var timeToFirstToken: TimeInterval = 0
        var completionInfo: GenerateCompletionInfo?

        if streaming {
            var pendingText = ""
            var lastFlushTime = Date()
            let flushInterval: TimeInterval = 0.1

            for try await item in stream {
                // Fix #4: Check for task cancellation cooperatively
                try Task.checkCancellation()
                if isCancelled { throw CancellationError() }

                switch item {
                case .chunk(let text):
                    fullOutput += text
                    pendingText += text
                    if timeToFirstToken == 0 {
                        timeToFirstToken = Date().timeIntervalSince(start)
                    }

                    let now = Date()
                    if now.timeIntervalSince(lastFlushTime) >= flushInterval {
                        output += pendingText
                        pendingText = ""
                        lastFlushTime = now
                    }
                case .info(let info):
                    completionInfo = info
                case .toolCall:
                    break
                }
            }

            // Flush any remaining text
            if !pendingText.isEmpty {
                output += pendingText
            }
        } else {
            // Non-streaming: collect everything then update once
            for try await item in stream {
                try Task.checkCancellation()
                if isCancelled { throw CancellationError() }

                switch item {
                case .chunk(let text):
                    fullOutput += text
                    if timeToFirstToken == 0 {
                        timeToFirstToken = Date().timeIntervalSince(start)
                    }
                case .info(let info):
                    completionInfo = info
                case .toolCall:
                    break
                }
            }

            output = fullOutput
        }

        // Update stats
        let ttftFormatted = timeToFirstToken.formatted(.number.precision(.fractionLength(2)))
        let tpsFormatted = (completionInfo?.tokensPerSecond ?? 0).formatted(.number.precision(.fractionLength(2)))
        stat = "TTFT: \(ttftFormatted)s | TPS: \(tpsFormatted)"
        logGPUMemoryUsage(at: "Generation Complete")

        return fullOutput
    }
    
    // Fix #1: Streaming generation that calls onChunk callback
    private func generateResponseStreaming(
        userInput: UserInput,
        modelContainer: ModelContainer,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws {
        logGPUMemoryUsage(at: "Generation Start")
        let parameters = generationParameters
        let start = Date()

        let input = try await modelContainer.prepare(input: userInput)
        let stream = try await modelContainer.generate(input: input, parameters: parameters)

        var fullOutput = ""
        var timeToFirstToken: TimeInterval = 0
        var completionInfo: GenerateCompletionInfo?
        var pendingText = ""
        var lastFlushTime = Date()
        let flushInterval: TimeInterval = 0.08

        for try await item in stream {
            try Task.checkCancellation()
            if isCancelled { throw CancellationError() }

            switch item {
            case .chunk(let text):
                fullOutput += text
                pendingText += text
                if timeToFirstToken == 0 {
                    timeToFirstToken = Date().timeIntervalSince(start)
                }

                let now = Date()
                if now.timeIntervalSince(lastFlushTime) >= flushInterval {
                    let textToFlush = pendingText
                    pendingText = ""
                    lastFlushTime = now
                    output += textToFlush
                    onChunk(textToFlush)
                }
            case .info(let info):
                completionInfo = info
            case .toolCall:
                break
            }
        }

        // Flush remaining text
        if !pendingText.isEmpty {
            output += pendingText
            onChunk(pendingText)
        }

        let ttftFormatted = timeToFirstToken.formatted(.number.precision(.fractionLength(2)))
        let tpsFormatted = (completionInfo?.tokensPerSecond ?? 0).formatted(.number.precision(.fractionLength(2)))
        stat = "TTFT: \(ttftFormatted)s | TPS: \(tpsFormatted)"
        logGPUMemoryUsage(at: "Generation Complete")
    }

    // Helper to build LLM input without generating
    private func buildLLMInput(systemPrompt: String?, userPrompt: String) -> UserInput {
        var messages: [Chat.Message] = []

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            messages.append(Chat.Message(role: .system, content: systemPrompt))
        }

        messages.append(Chat.Message(role: .user, content: userPrompt))

        return UserInput(
            chat: messages,
            additionalContext: ["enable_thinking": self.enableThinking]
        )
    }

    // Process with LLM using proper Chat.Message format
    private func processWithLLM(
        modelContainer: ModelContainer,
        systemPrompt: String?,
        userPrompt: String,
        streaming: Bool
    ) async throws -> String {
        let userInput = buildLLMInput(systemPrompt: systemPrompt, userPrompt: userPrompt)

        return try await generateResponse(
            userInput: userInput,
            modelContainer: modelContainer,
            streaming: streaming
        )
    }
    
    // Fix #12: Collect temp URLs in a separate array for cleanup even on partial failure
    private func buildVLMInput(systemPrompt: String?, userPrompt: String, images: [Data]) throws -> (input: UserInput, tempURLs: [URL]) {
        var tempURLs: [URL] = []

        // Ensure cleanup of any written temp files on error
        do {
            let imageURLs = try images.compactMap { imageData -> URL? in
                // Check if image data is already in a VLM-compatible format (PNG or JPEG)
                let isPNG = imageData.count >= 8 && imageData.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                let isJPEG = imageData.count >= 3 && imageData.prefix(3).elementsEqual([0xFF, 0xD8, 0xFF])

                let fileURL: URL
                if isPNG {
                    fileURL = Self.makeManagedTempImageURL(pathExtension: "png")
                    try imageData.write(to: fileURL)
                } else if isJPEG {
                    fileURL = Self.makeManagedTempImageURL(pathExtension: "jpg")
                    try imageData.write(to: fileURL)
                } else {
                    // For other formats, use CGImage directly
                    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                        logger.warning("Could not create CGImage from image data")
                        return nil
                    }

                    fileURL = Self.makeManagedTempImageURL(pathExtension: "png")

                    guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                        logger.warning("Could not create image destination")
                        return nil
                    }
                    CGImageDestinationAddImage(destination, cgImage, nil)
                    guard CGImageDestinationFinalize(destination) else {
                        logger.warning("Could not finalize image destination")
                        return nil
                    }
                }

                tempURLs.append(fileURL)
                return fileURL
            }

            // Early return if no valid images
            if imageURLs.isEmpty && !images.isEmpty {
                // Clean up any partial temp files
                for url in tempURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                logger.warning("Failed to process all images for VLM")
                throw NSError(domain: "LocalModelProvider", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to process images for vision model"])
            }

            var messages: [Chat.Message] = []

            if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                messages.append(Chat.Message(role: .system, content: systemPrompt))
            }

            let imageAttachments: [UserInput.Image] = imageURLs.map { .url($0) }

            messages.append(Chat.Message(
                role: .user,
                content: userPrompt,
                images: imageAttachments
            ))

            let userInput = UserInput(
                chat: messages,
                additionalContext: ["enable_thinking": self.enableThinking]
            )
            return (input: userInput, tempURLs: tempURLs)
        } catch {
            // Clean up all temp files on any error
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    private func processWithVLM(
        modelContainer: ModelContainer,
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        streaming: Bool
    ) async throws -> String {
        let (userInput, tempURLs) = try buildVLMInput(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)

        // Temp files must remain valid during generation (MLX reads them in prepare()).
        // Clean up after generation completes or fails.
        defer {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        return try await generateResponse(
            userInput: userInput,
            modelContainer: modelContainer,
            streaming: streaming
        )
    }
    
    // Fix #4: Proper cancellation that stops in-flight generation
    func cancel() {
        if running {
            logger.debug("Cancelling in-flight generation...")
            isCancelled = true
            generationTask?.cancel()
            generationTask = nil
        }
        running = false
        isProcessing = false
        // Don't cancel download here, that's separate
    }

    // MARK: - Memory Reclamation

    /// Drops the in-memory model container and returns MLX's cached GPU buffers
    /// to the system. Safe to call repeatedly. Does NOT touch the on-disk
    /// weights, so a subsequent generation simply re-loads from disk.
    private func releaseLoadedModelMemory() {
        cachedContainer = nil
        Memory.clearCache()
    }

    /// Unloads the loaded model and reclaims its memory.
    ///
    /// A loaded 4-bit model can pin several GB of unified memory plus GPU
    /// buffers for the whole app lifetime. We release it when the user switches
    /// away from the local provider or when the system reports memory pressure.
    /// `loadState` drops from `.loaded` back to `.downloaded`; the weights stay
    /// on disk. This is a no-op while a generation or load is in flight so we
    /// never tear the model out from under active work.
    func unload() {
        guard !running, loadState != .loading else { return }

        let hadModel = cachedContainer != nil
        releaseLoadedModelMemory()

        if case .loaded = loadState {
            loadState = .downloaded
        }

        if hadModel {
            logger.debug("Unloaded local model and cleared GPU cache")
            logGPUMemoryUsage(at: "unload")
        }
    }

    /// Listens for system memory-pressure warnings and proactively unloads the
    /// model to avoid being jetsammed on memory-constrained Macs.
    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                logger.warning("Memory pressure detected — unloading local model")
                self.cancel()
                self.unload()
            }
        }
        source.resume()
        memoryPressureSource = source
    }
}

extension LocalModelProvider: @MainActor AIProvider {}
