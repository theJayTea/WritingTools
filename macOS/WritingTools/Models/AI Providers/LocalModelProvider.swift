import MLX
import MLXVLM
import MLXLLM
import MLXLMCommon
import MLXRandom
import SwiftUI
import Combine

// Constants for UserDefaults keys
fileprivate let kModelStatusKey = "local_llm_model_status"
fileprivate let kModelInfoKey = "local_llm_model_info"

@MainActor
class LocalModelProvider: ObservableObject, AIProvider {
    
    @ObservedObject private var settings = AppSettings.shared
    private var settingsCancellable: AnyCancellable?
    
    @Published var isProcessing = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadTask: Task<ModelContainer, Error>?
    @Published var output = ""
    @Published var modelInfo = ""
    @Published var stat = ""
    @Published var lastError: String?
    @Published var retryCount: Int = 0
    
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
    
    let generateParameters = GenerateParameters(temperature: 0.6)
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
        guard let documentsPath = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else {
            print("Could not find Documents directory")
            return nil
        }
        let idstring = String(describing: config.id)
        let cleanId = idstring.replacingOccurrences(of: "id(\"", with: "")
            .replacingOccurrences(of: "\")", with: "")
        let modelPath = "huggingface/models/\(cleanId)" // Use the ID of the selected model
        return documentsPath.appendingPathComponent(modelPath)
    }
    
    init() {
        if isPlatformSupported {
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
            
            settingsCancellable = settings.$selectedLocalLLMId.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    // When the selection changes, reset state and check the new model
                    self?.resetModelState()
                    self?.checkModelStatus()
                }
            }
            checkModelStatus()
            
        } else {
            modelInfo = "Local LLM is only available on Apple Silicon devices"
            loadState = .error("Platform not supported")
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
            print("checkModelStatus: Skipping check, currently downloading or loading.")
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
                    print("Error reading directory contents: \(error)")
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
                print("checkModelStatus: Removed empty directory at \(modelDir.path)")
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
            print("startDownload: Download already in progress or task exists.")
            return
        }
        // Prevent starting if already downloaded/loading/loaded
        guard loadState == .needsDownload || loadState == .error("Download failed") || loadState == .idle || loadState == .checking else {
            print("startDownload: Cannot start download from state \(loadState).")
            // Update info based on state
            switch loadState {
            case .downloaded, .loaded: modelInfo = "\(selectedModelType?.displayName ?? "Model") is already available."
            case .loading: modelInfo = "\(selectedModelType?.displayName ?? "Model") is loading."
            default: break
            }
            return
        }
        
        
        print("startDownload: Proceeding to initiate download for \(selectedModelType?.displayName ?? "Unknown").")
        
        isCancelled = false
        retryCount = 0
        lastError = nil
        isDownloading = true
        downloadProgress = 0
        modelInfo = "Starting download for \(selectedModelType?.displayName ?? "model")..."
        loadState = .needsDownload
        
        downloadTask = Task {
            print("startDownload: Task created, calling load()")
            do {
                let container = try await load()
                // Success is handled within load() by setting state to .loaded
                print("startDownload: Task finished successfully.")
                return container
            } catch {
                // Errors (including cancellation) are handled within load()
                print("startDownload: Task finished with error: \(error)")
                throw error
            }
        }
        print("startDownload: downloadTask assigned.")
    }
    
    // --- cancelDownload ---
    func cancelDownload() {
        guard isPlatformSupported else { return }
        
        // Only proceed if a download is actually in progress
        guard isDownloading, let task = downloadTask else {
            print("cancelDownload: No active download task to cancel.")
            isDownloading = false
            downloadTask = nil
            isCancelled = false
            return
        }
        
        print("cancelDownload: Initiating cancellation...")
        
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
            print("retryDownload: Cannot retry while another download is active.")
            modelInfo = "Cannot retry: another download is active."
            return
        }
        
        retryCount += 1
        loadState = .needsDownload
        lastError = nil
        modelInfo = "Retrying download (\(retryCount)/\(maxRetries)) for \(selectedModelType?.displayName ?? "model")..."
        print("retryDownload: Attempting retry \(retryCount)/\(maxRetries)")
        startDownload()
    }
    
    func deleteModel() throws {
        guard isPlatformSupported else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Platform not supported"])
        }
        guard let modelDir = modelDirectory, let modelType = selectedModelType else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model selected to delete."])
        }
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
                print("Model directory deleted: \(modelDir.path)")
            } else if exists { // It's a file? Try deleting anyway.
                try FileManager.default.removeItem(at: modelDir)
                print("Warning: Expected directory but found file at \(modelDir.path), removed.")
            } else {
                print("Model directory not found, nothing to delete: \(modelDir.path)")
            }
            
            // Reset state *after* successful deletion or if not found
            resetModelState() // Reset everything
            checkModelStatus() // Re-check, should now be .needsDownload
            modelInfo = "\(modelType.displayName) deleted." // Update info *after* check
            
        } catch {
            print("Failed to delete model \(modelType.displayName): \(error)")
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
        
        print("load: Function called. Current state: \(loadState)")
        
        if case .loaded(let container) = loadState {
            print("load: Model already loaded.")
            return container
        }
        if case .loading = loadState {
            print("load: Model is already loading (called directly?).")
            // Wait for existing load? For now, throw error.
            throw NSError(domain: "LocalLLM", code: -3, userInfo: [NSLocalizedDescriptionKey: "Model is already loading."])
        }
        
        // Reset cancellation flag for this specific attempt
        // Note: isCancelled might be true if cancelDownload was called just before load started
        // isCancelled = false // Let's rely on the flag set by cancelDownload
        
        // --- Download Block ---
        if case .needsDownload = loadState {
            print("load: State is .needsDownload. Preparing to download \(modelType.displayName).")
            // Ensure flags are accurate, though startDownload should have set them
            isDownloading = true
            // downloadProgress = 0 // Keep existing progress if resuming? No, start fresh.
            // modelInfo = "Downloading \(modelType.displayName)..." // Keep info from startDownload
            
            do {
                // Select the appropriate factory based on whether it's a vision model
                let factory: ModelFactory = modelType.isVisionModel
                ? VLMModelFactory.shared
                : LLMModelFactory.shared
                
                print("load: Calling \(modelType.isVisionModel ? "VLM" : "LLM")ModelFactory.shared.loadContainer for \(config.id)")
                
                let modelContainer = try await factory.loadContainer(
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
                print("load: loadContainer completed successfully for download.")
                isDownloading = false
                downloadProgress = 1.0
                downloadTask = nil // Clear task reference
                let numParams = await modelContainer.perform { context in context.model.numParameters() }
                modelInfo = "\(modelType.displayName) loaded. Weights: \(numParams / (1024 * 1024))M"
                loadState = .loaded(modelContainer)
                print("load: State set to .loaded")
                return modelContainer
                
            } catch { // Catch ALL errors here
                // --- Download Error/Cancellation ---
                print("load: Error during loadContainer (download): \(error), isCancelled flag: \(isCancelled)")
                
                // Determine if it was a user cancellation
                let wasExplicitlyCancelled = isCancelled // Check our flag first
                let isCancellationError = error is CancellationError || (error as NSError).code == NSUserCancelledError
                
                // --- Important: Reset flags *before* updating state/checking status ---
                isDownloading = false
                downloadProgress = 0
                downloadTask = nil // Clear task reference
                
                if wasExplicitlyCancelled || isCancellationError {
                    print("load: Download cancelled.")
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
                    print("load: State set to .error")
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
            print("load: State is .downloaded. Loading \(modelType.displayName) from disk.")
            loadState = .loading
            modelInfo = "Loading \(modelType.displayName)..."
            do {
                let factory: ModelFactory = modelType.isVisionModel
                ? VLMModelFactory.shared
                : LLMModelFactory.shared
                
                print("load: Calling \(modelType.isVisionModel ? "VLM" : "LLM")ModelFactory.shared.loadContainer for \(config.id)")
                let modelContainer = try await factory.loadContainer(configuration: config)
                print("load: loadContainer completed successfully (from disk).")
                let numParams = await modelContainer.perform { context in context.model.numParameters() }
                modelInfo = "\(modelType.displayName) loaded. Weights: \(numParams / (1024 * 1024))M"
                loadState = .loaded(modelContainer)
                print("load: State set to .loaded")
                return modelContainer
            } catch let error as NSError {
                print("load: Error during loadContainer (from disk): \(error)")
                lastError = "Error loading \(modelType.displayName): \(error.localizedDescription)"
                modelInfo = lastError!
                loadState = .error(lastError!)
                print("load: State set to .error")
                // Optionally call checkModelStatus here too if loading error might change things
                // checkModelStatus()
                throw error
            }
            // --- Other States ---
        } else {
            print("load: Cannot load model from current state: \(loadState)")
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
            print("Generation already in progress, waiting...")
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
            print("Failed to load model for processing: \(error)")
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
                    images: images
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
                    userPrompt: combinedPrompt
                )
            }
        } catch {
            // Handle generation errors
            print("Error during text generation: \(error)")
            await MainActor.run { [weak self] in
                self?.lastError = "Generation failed: \(error.localizedDescription)"
                self?.stat = "Error"
            }
            throw error
        }
    }
    
    // New method to process with LLM
    private func processWithLLM(
        modelContainer: ModelContainer,
        systemPrompt: String?,
        userPrompt: String
    ) async throws -> String {
        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        
        let result = try await modelContainer.perform { [weak self] context in
            guard let self = self else {
                throw NSError(domain: "LocalModelProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "Provider deallocated"])
            }
            
            // Create final prompt with system prompt if available
            let finalPrompt = systemPrompt.map { "\($0)\n\nUser:\n\(userPrompt)" } ?? "User:\n\(userPrompt)"
            
            // Prepare input for the model
            let userInput = await UserInput(
                prompt: finalPrompt,
                additionalContext: ["enable_thinking": self.enableThinking]
            )
            let input = try await context.processor.prepare(input: userInput)
            
            // Generate text
            return try MLXLMCommon.generate(
                input: input,
                parameters: self.generateParameters,
                context: context
            ) { [weak self] tokens in
                guard let self = self else { return .stop }
                if tokens.count >= self.maxTokens { return .stop }
                else { return .more }
            }
        }
        
        // Update published properties
        await MainActor.run { [weak self] in
            self?.output = result.output
            self?.stat = "Tokens/second: \(String(format: "%.3f", result.tokensPerSecond))"
        }
        
        return result.output
    }
    
    // New method to process with VLM
    private func processWithVLM(
        modelContainer: ModelContainer,
        systemPrompt: String?,
        userPrompt: String,
        images: [Data]
    ) async throws -> String {
        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        
        // Create temporary URLs for images with better format handling
        let imageURLs = try images.compactMap { imageData -> URL? in
            // First try to create an NSImage from the data
            guard let nsImage = NSImage(data: imageData) else {
                print("Warning: Could not create NSImage from image data")
                return nil
            }
            
            // Convert to PNG format for better compatibility with VLMs
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                print("Warning: Could not convert image to PNG format")
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
            print("Warning: Failed to process all images for VLM")
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
            let result = try await modelContainer.perform { [weak self] context in
                guard let self = self else {
                    throw NSError(domain: "LocalModelProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "Provider deallocated"])
                }
                
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
                let input = try await context.processor.prepare(input: userInput)
                
                // Generate text
                return try MLXLMCommon.generate(
                    input: input,
                    parameters: self.generateParameters,
                    context: context
                ) { [weak self] tokens in
                    guard let self = self else { return .stop }
                    if tokens.count >= self.maxTokens { return .stop }
                    else { return .more }
                }
            }
            
            // Update published properties
            await MainActor.run { [weak self] in
                self?.output = result.output
                self?.stat = "Tokens/second: \(String(format: "%.3f", result.tokensPerSecond))"
            }
            
            return result.output
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
                print("Attempting to cancel generation...")
                // You might need more sophisticated cancellation if MLXLLM adds support
            }
            running = false
            isProcessing = false
            // Don't cancel download here, that's separate
        }
    }
}
