import MLX
import MLXVLM
import MLXLLM
import MLXLMCommon
import MLXRandom
import SwiftUI
import Combine
import Observation
import Hub

private let logger = AppLogger.logger("LocalModelProvider")

// Constants for UserDefaults keys
fileprivate let kModelStatusKey = "local_llm_model_status"
fileprivate let kModelInfoKey = "local_llm_model_info"


@MainActor
class LocalModelProvider: ObservableObject, AIProvider {
    
    private let settings = AppSettings.shared
    
    @Published var isProcessing = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadTask: Task<ModelContainer, Error>?
    @Published var output = ""
    @Published var modelInfo = ""
    @Published var stat = ""
    @Published var lastError: String?
    @Published var retryCount: Int = 0

    // Keep already loaded models alive so we don't pay the load cost after a model switch.
    private let modelCache = NSCache<NSString, ModelContainer>()
    
    var running = false
    private var isCancelled = false
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("WritingTools/MLXModels", isDirectory: true)
    }()

    private lazy var hub: HubApi = {
        // ensure the folder exists
        try? FileManager.default.createDirectory(at: Self.modelsRoot, withIntermediateDirectories: true)
        return HubApi(downloadBase: Self.modelsRoot)
    }()

    // Is the current platform supported
    var isPlatformSupported: Bool {
        LocalModelProvider.isAppleSilicon
    }
    
    // Use default model from registry.
    //let modelConfiguration : ModelConfiguration = .qwen2_5_3b_4bit
    //let modelConfiguration = LLMRegistry.llama3_2_3B_4bit
    
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
    
    private func cleanID(from config: ModelConfiguration) -> String {
        var s = String(describing: config.id)
        if s.hasPrefix("id(\""), s.hasSuffix("\")") {
            s.removeFirst(4); s.removeLast(2)
        }
        return s
    }

    private func cacheKey(for config: ModelConfiguration) -> NSString {
        NSString(string: cleanID(from: config))
    }

    private func expectedRepoFolder(for config: ModelConfiguration) -> URL {
        let id = cleanID(from: config)                 // e.g. "mlx-community/gemma-3-4b-it-qat-4bit"
        let parts = id.split(separator: "/")
        if parts.count == 2 {
            return Self.modelsRoot
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(String(parts[0]), isDirectory: true)
                .appendingPathComponent(String(parts[1]), isDirectory: true)
        } else {
            // fallback: flatten if id is unexpected
            return Self.modelsRoot
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(id.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        }
    }

    
    private var generationParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            temperature: 0.6
        )
    }
    let maxTokens = 10000
    let displayEveryNTokens = 4
    
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
    
    @Published var loadState = LoadState.idle
    
    // Model Directory Calculation
    private var modelDirectory: URL? {
         guard let config = selectedModelConfiguration else { return nil }
         return expectedRepoFolder(for: config)
     }
    
    init() {
        modelCache.countLimit = 2
        if isPlatformSupported {
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
            
            observeSettings()
            checkModelStatus()
            
        } else {
            modelInfo = "Local LLM is only available on Apple Silicon devices"
            loadState = .error("Platform not supported")
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.selectedLocalLLMId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                // When the selection changes, reset state and check the new model.
                self?.resetModelState()
                self?.checkModelStatus()
                self?.observeSettings()
            }
        }
    }
    
    // --- Reset state when model selection changes ---
    private func resetModelState() {
        cancelDownload()
        cancel()
        
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
    
    private func checkModelStatus() {
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
        
        
        loadState = .checking
        modelInfo = "Checking status for \(modelType.displayName)..."
        
        let fileCoordinator = NSFileCoordinator()
        var fileError: NSError?
        var exists = false
        var isDirectory: ObjCBool = false
        var isEmpty = true
        
        fileCoordinator.coordinate(readingItemAt: modelDir, options: .withoutChanges, error: &fileError) { url in
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
        
        if let fileError = fileError {
            loadState = .error("Error checking model directory: \(fileError.localizedDescription)")
            modelInfo = "Error checking \(modelType.displayName)."
            lastError = fileError.localizedDescription
        } else if exists && isDirectory.boolValue && !isEmpty {
            loadState = .downloaded
            modelInfo = "\(modelType.displayName) is downloaded."
        } else {
            if exists && isDirectory.boolValue && isEmpty {
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
        guard loadState == .needsDownload || loadState == .error("Download failed") || loadState == .idle || loadState == .checking else {
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
        
        downloadTask = Task {
            logger.debug("startDownload: Task created, calling load()")
            do {
                let container = try await load()
                // Success is handled within load() by setting state to .loaded
                logger.debug("startDownload: Task finished successfully.")
                return container
            } catch {
                // Errors (including cancellation) are handled within load()
                logger.error("startDownload: Task finished with error: \(error.localizedDescription)")
                throw error
            }
        }
        logger.debug("startDownload: downloadTask assigned.")
    }
    
    // --- cancelDownload ---
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
        
        // --- Immediate UI Update ---
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
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Self.modelsRoot.path)
    }

    func cleanLegacyCacheForSelectedModel() {
        // If you want to remove any old cached copy (previous defaultHubApi downloads)
        guard let config = selectedModelConfiguration else { return }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        // MLX’s default hub uses caches; structure may vary—remove any folders that contain the repo name
        let repo = cleanID(from: config).split(separator: "/").last.map(String.init) ?? ""
        if let contents = try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.localizedCaseInsensitiveContains(repo) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    
    func deleteModel() throws {
        guard isPlatformSupported else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Platform not supported"])
        }
        guard let modelDir = modelDirectory, let modelType = selectedModelType else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected to delete."])
        }
        let cacheKey = cacheKey(for: modelType.configuration)
        guard !isDownloading && !running && loadState != .loading else { // Also check loading state
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot delete while model is busy (downloading, running, or loading)"])
        }
        
        if case .loaded = loadState {
            loadState = .downloaded
        }
        
        do {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDirectory)
            
            if exists && isDirectory.boolValue {
                try FileManager.default.removeItem(at: modelDir)
                logger.debug("Model directory deleted: \(modelDir.path)")
            } else if exists { // It's a file? Try deleting anyway.
                try FileManager.default.removeItem(at: modelDir)
                logger.warning("Expected directory but found file at \(modelDir.path), removed.")
            } else {
                logger.debug("Model directory not found, nothing to delete: \(modelDir.path)")
            }
            
            // Reset state *after* successful deletion or if not found
            resetModelState() // Reset everything
            modelCache.removeObject(forKey: cacheKey)
            checkModelStatus() // Re-check, should now be .needsDownload
            modelInfo = "\(modelType.displayName) deleted." // Update info *after* check
            
        } catch {
            logger.error("Failed to delete model \(modelType.displayName): \(error.localizedDescription)")
            lastError = "Failed to delete \(modelType.displayName): \(error.localizedDescription)"
            modelInfo = lastError!
            loadState = .error(lastError!)
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
        let cacheKey = cacheKey(for: config)
        
        logger.debug("load: Function called. Current state: \(String(describing: self.loadState))")

        if let cached = modelCache.object(forKey: cacheKey) {
            loadState = .loaded(cached)
            modelInfo = "\(modelType.displayName) is ready (cached)."
            return cached
        }

        if case .loaded(let container) = loadState {
            logger.debug("load: Model already loaded.")
            modelCache.setObject(container, forKey: cacheKey)
            return container
        }
        if case .loading = loadState {
            logger.debug("load: Model is already loading (called directly?).")
            // Wait for existing load? For now, throw error.
            throw NSError(domain: "LocalLLM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Model is already loading."])
        }
        
        // Reset cancellation flag for this specific attempt
        // Note: isCancelled might be true if cancelDownload was called just before load started
        // isCancelled = false // Let's rely on the flag set by cancelDownload
        
        // --- Download Block ---
        if case .needsDownload = loadState {
            logger.debug("load: State is .needsDownload. Preparing to download \(modelType.displayName).")
            // Ensure flags are accurate, though startDownload should have set them
            isDownloading = true
            // downloadProgress = 0 // Keep existing progress if resuming? No, start fresh.
            // modelInfo = "Downloading \(modelType.displayName)..." // Keep info from startDownload
            
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
                modelCache.setObject(modelContainer, forKey: cacheKey)
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
                    lastError = "Download cancelled." // Set user-facing error
                    modelInfo = lastError!
                    // State should revert correctly after checkModelStatus
                } else {
                    // Handle other errors (network, disk space, etc.)
                    let nsError = error as NSError
                    lastError = nsError.domain == NSURLErrorDomain
                    ? "Network error downloading \(modelType.displayName): \(nsError.localizedDescription)"
                    : "Error downloading \(modelType.displayName): \(nsError.localizedDescription)"
                    modelInfo = lastError ?? "Unknown download error"
                    loadState = .error(lastError!) // Set error state immediately
                    logger.error("load: State set to .error")
                }
                
                // Always re-check status after failure/cancellation to update UI correctly
                checkModelStatus()
                
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
                let numParams = await modelContainer.perform { context in context.model.numParameters() }
                modelInfo = "\(modelType.displayName) loaded. Weights: \(numParams / (1024 * 1024))M"
                modelCache.setObject(modelContainer, forKey: cacheKey)
                loadState = .loaded(modelContainer)
                logger.debug("load: State set to .loaded")
                return modelContainer
            } catch let error as NSError {
                logger.error("load: Error during loadContainer (from disk): \(error.localizedDescription)")
                lastError = "Error loading \(modelType.displayName): \(error.localizedDescription)"
                modelInfo = lastError!
                loadState = .error(lastError!)
                logger.error("load: State set to .error")
                // Optionally call checkModelStatus here too if loading error might change things
                // checkModelStatus()
                throw error
            }
            // --- Other States ---
        } else {
            logger.warning("load: Cannot load model from current state: \(String(describing: self.loadState))")
            throw NSError(domain: "LocalLLM", code: -5, userInfo: [NSLocalizedDescriptionKey: "Cannot load model from current state: \(loadState)"])
        }
    }
    
    func processText(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool = false) async throws -> String {
        guard isPlatformSupported else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Platform not supported"])
        }
        guard selectedModelConfiguration != nil else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected for processing."])
        }
        
        if running {
            logger.debug("Generation already in progress, waiting...")
            while running { try await Task.sleep(for: .milliseconds(100)) }
        }
        
        running = true
        isProcessing = true
        output = ""
        
        defer {
            Task { @MainActor [weak self] in
                self?.running = false
                self?.isProcessing = false
            }
        }
        
        // Load the model
        let modelContainer: ModelContainer
        do {
            modelContainer = try await load()
        } catch {
            logger.error("Failed to load model for processing: \(error.localizedDescription)")
            throw error
        }
        
        // Prepare input based on model type and available inputs
        do {
            if isUsingVisionModel && !images.isEmpty {
                // VLM with images
                return try await processWithVLM(
                    modelContainer: modelContainer,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    images: images,
                    streaming: streaming
                )
            } else {
                // Regular LLM or VLM without images
                // If using VLM without images, we'll just use it as a regular LLM
                // If using LLM with images, we'll use OCR and include text in prompt
                
                var combinedPrompt = userPrompt
                if !images.isEmpty && !isUsingVisionModel {
                    let ocrText = await OCRManager.shared.extractText(from: images)
                    if !ocrText.isEmpty {
                        combinedPrompt += "\n\n[Extracted Text from Image(s)]:\n\(ocrText)"
                    }
                }
                
                return try await processWithLLM(
                    modelContainer: modelContainer,
                    systemPrompt: systemPrompt,
                    userPrompt: combinedPrompt,
                    streaming: streaming
                )
            }
        } catch {
            // Handle generation errors
            logger.error("Error during text generation: \(error.localizedDescription)")
            await MainActor.run { [weak self] in
                self?.lastError = "Generation failed: \(error.localizedDescription)"
                self?.stat = "Error"
            }
            throw error
        }
    }
    
    private struct GenerationResult {
        let text: String
        let info: GenerateCompletionInfo?
        let timeToFirstToken: TimeInterval?
        let trailingFlush: String
    }

    private func generateResponse(
        userInput: UserInput,
        modelContainer: ModelContainer,
        streaming: Bool
    ) async throws -> String {
        let parameters = generationParameters
        let flushEvery = displayEveryNTokens
        let start = Date()

        let result = try await modelContainer.perform { context in
            var output = ""
            var completion: GenerateCompletionInfo?
            var timeToFirstToken: TimeInterval?
            var pendingFlush = ""
            var tokensSinceFlush = 0

            let input = try await context.processor.prepare(input: userInput)
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            )

            for try await item in stream {
                switch item {
                case .chunk(let string):
                    output += string
                    if timeToFirstToken == nil {
                        timeToFirstToken = Date().timeIntervalSince(start)
                    }

                    if streaming {
                        pendingFlush += string
                        tokensSinceFlush += 1

                        let shouldFlush = tokensSinceFlush == 1 || tokensSinceFlush >= flushEvery
                        if shouldFlush {
                            let flush = pendingFlush
                            pendingFlush.removeAll()
                            tokensSinceFlush = 0
                            await MainActor.run { [weak self] in
                                self?.output += flush
                            }
                        }
                    }
                case .info(let info):
                    completion = info
                case .toolCall:
                    break
                }
            }

            return GenerationResult(
                text: output,
                info: completion,
                timeToFirstToken: timeToFirstToken,
                trailingFlush: pendingFlush
            )
        }

        if streaming {
            if !result.trailingFlush.isEmpty {
                await MainActor.run { [weak self] in
                    self?.output += result.trailingFlush
                }
            }
        } else {
            await MainActor.run { [weak self] in
                self?.output = result.text
            }
        }

        let ttft = result.timeToFirstToken ?? 0
        let tps = result.info?.tokensPerSecond ?? 0
        await MainActor.run { [weak self] in
            self?.stat = "TTFT: \(String(format: "%.2f", ttft))s | TPS: \(String(format: "%.2f", tps))"
        }

        return result.text
    }
    
    // New method to process with LLM
    private func processWithLLM(
        modelContainer: ModelContainer,
        systemPrompt: String?,
        userPrompt: String,
        streaming: Bool
    ) async throws -> String {
        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

        let finalPrompt = systemPrompt.map { "\($0)\n\nUser:\n\(userPrompt)" } ?? "User:\n\(userPrompt)"
        let userInput = await UserInput(
            prompt: finalPrompt,
            additionalContext: ["enable_thinking": self.enableThinking]
        )

        return try await generateResponse(
            userInput: userInput,
            modelContainer: modelContainer,
            streaming: streaming
        )
    }
    
    // New method to process with VLM
    private func processWithVLM(
        modelContainer: ModelContainer,
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        streaming: Bool
    ) async throws -> String {
        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        
        // Create temporary URLs for images with better format handling
        let imageURLs = try images.compactMap { imageData -> URL? in
            // First try to create an NSImage from the data
            guard let nsImage = NSImage(data: imageData) else {
                logger.warning("Could not create NSImage from image data")
                return nil
            }
            
            // Convert to PNG format for better compatibility with VLMs
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                logger.warning("Could not convert image to PNG format")
                return nil
            }
            
            // Create temp file with PNG extension
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString + ".png"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            // Write PNG data to file
            try pngData.write(to: fileURL)
            return fileURL
        }
        
        // Early return if no valid images
        if imageURLs.isEmpty && !images.isEmpty {
            logger.warning("Failed to process all images for VLM")
            throw NSError(domain: "LocalModelProvider", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to process images for vision model"])
        }
        
        // Clean up temp files when we're done
        defer {
            for url in imageURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // Increase GPU memory limit for VLM models
        MLX.GPU.set(cacheLimit: 4 * 1024 * 1024 * 1024) // 4GB cache limit
        
        do {
            // Create a chat-style input with images
            var messages: [Chat.Message] = []
            
            // Add system message if provided
            if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                messages.append(Chat.Message(role: .system, content: systemPrompt))
            }
            
            // Convert image URLs to the format expected by MLX
            let imageAttachments: [UserInput.Image] = imageURLs.map { .url($0) }
            
            // Add user message with text and images
            messages.append(Chat.Message(
                role: .user,
                content: userPrompt,
                images: imageAttachments
            ))
            
            // Create chat input
            let userInput = await UserInput(
                chat: messages,
                additionalContext: ["enable_thinking": self.enableThinking]
            )

            return try await generateResponse(
                userInput: userInput,
                modelContainer: modelContainer,
                streaming: streaming
            )
        } catch {
            // Reset GPU cache on error
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
            throw error
        }
    }
    
    
    func cancel() {
        // Cancel ongoing generation (MLXLLM doesn't have explicit cancellation for generate,
        // but setting running = false prevents new ones and stops the wait loop)
        Task { @MainActor in
            if running {
                logger.debug("Attempting to cancel generation...")
                // You might need more sophisticated cancellation if MLXLLM adds support
            }
            running = false
            isProcessing = false
            // Don't cancel download here, that's separate
        }
    }
}
