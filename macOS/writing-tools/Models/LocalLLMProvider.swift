import MLX
import MLXLLM
import MLXLMCommon
import MLXRandom
import SwiftUI

@MainActor
class LocalLLMProvider: ObservableObject, AIProvider {
    
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
    private let modelDirectory: URL
    private let maxRetries = 3
    
    // Use default model from registry.
    //let modelConfiguration : ModelConfiguration = .qwen2_5_7b_1M_4bit
    let modelConfiguration = ModelRegistry.llama3_2_3B_4bit
    let generateParameters = GenerateParameters(temperature: 0.6)
    let maxTokens = 1000000
    let displayEveryNTokens = 4

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }
    
    var loadState = LoadState.idle
    
    init() {
        guard let documentsPath = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else {
            print("Could not find Documents directory")
            modelDirectory = FileManager.default.temporaryDirectory
            return
        }
        let modelPath = "huggingface/models/\(modelConfiguration.id)"
        modelDirectory = documentsPath.appendingPathComponent(modelPath)
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        checkModelStatus()
    }
    
    private func checkModelStatus() {
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            let modelFiles = try? FileManager.default.contentsOfDirectory(
                atPath: modelDirectory.path)
            if modelFiles?.isEmpty == false {
                loadState = .idle // Model loads on demand.
                modelInfo = "Model available"
            } else {
                loadState = .idle
                modelInfo = "Model needs to be downloaded"
            }
        } else {
            loadState = .idle
            modelInfo = "Model needs to be downloaded"
        }
    }
    
    func startDownload() {
        guard downloadTask == nil else { return }
        isCancelled = false
        retryCount = 0
        
        downloadTask = Task {
            return try await load()
        }
    }
    
    func cancelDownload() {
        isCancelled = true
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
        modelInfo = "Download cancelled"
        lastError = nil
    }
    
    func retryDownload() {
        guard retryCount < maxRetries else {
            lastError = "Maximum retry attempts reached"
            return
        }
        retryCount += 1
        startDownload()
    }
    
    func deleteModel() throws {
        guard !isDownloading && !running else {
            throw NSError(
                domain: "LocalLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot delete while model is in use"]
            )
        }
        
        do {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: modelDirectory.path, isDirectory: &isDirectory)
            guard exists && isDirectory.boolValue else {
                throw NSError(
                    domain: "LocalLLM",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Model directory not found"]
                )
            }
            try FileManager.default.removeItem(at: modelDirectory)
            loadState = .idle
            modelInfo = "Model deleted"
            lastError = nil
            print("Model directory deleted: \(modelDirectory.path)")
        } catch {
            print("Failed to delete model: \(error)")
            throw error
        }
    }
    
    func load() async throws -> ModelContainer {
        guard !isCancelled else { throw CancellationError() }
        switch loadState {
        case .idle:
            isDownloading = true
            downloadProgress = 0
            lastError = nil
            
            do {
                let modelContainer = try await LLMModelFactory.shared.loadContainer(
                    configuration: modelConfiguration
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, !self.isCancelled else { return }
                        self.downloadProgress = progress.fractionCompleted
                        self.modelInfo = "Downloading \(self.modelConfiguration.name): " +
                        "\(Int(progress.fractionCompleted * 100))%"
                    }
                }
                
                let numParams = await modelContainer.perform { context in
                    context.model.numParameters()
                }
                isDownloading = false
                downloadProgress = 1.0
                modelInfo = "Loaded \(modelConfiguration.id). Weights: \(numParams / (1024 * 1024))M"
                loadState = .loaded(modelContainer)
                downloadTask = nil
                return modelContainer
                
            } catch let error as NSError {
                isDownloading = false
                downloadProgress = 0
                lastError = error.domain == NSURLErrorDomain
                    ? "Network error: \(error.localizedDescription)"
                    : "Error: \(error.localizedDescription)"
                modelInfo = lastError ?? "Unknown error occurred"
                downloadTask = nil
                throw error
            }
            
        case .loaded(let modelContainer):
            return modelContainer
        }
    }
    
    func processText(systemPrompt: String?, userPrompt: String, images: [Data]) async throws -> String {
        // Remove the immediate error throw if already running.
        // Instead, if already running, print a debug message and wait.
        if running {
            print("Generation already in progress, waiting for the current process...")
            // Optionally, you could wait or cancel the previous generation.
            // For this update, we simply wait until the previous generation ends.
            while running { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        
        running = true
        isProcessing = true
        output = ""
        
        defer {
            Task { @MainActor in
                self.running = false
                self.isProcessing = false
            }
        }
        
        let finalPrompt = systemPrompt.map { "\($0)\n\n\(userPrompt)" }
            ?? userPrompt
        
        let modelContainer = try await load()
        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        
        let result = try await modelContainer.perform { [weak self] context in
            let input = try await context.processor.prepare(
                input: .init(prompt: finalPrompt)
            )
            return try MLXLMCommon.generate(
                input: input,
                parameters: self?.generateParameters ?? GenerateParameters(temperature: 0.6),
                context: context
            ) { [weak self] tokens in
                if tokens.count >= (self?.maxTokens ?? 1000000) {
                    return .stop
                } else {
                    return .more
                }
            }
        }
        
        DispatchQueue.main.async {
            self.output = result.output
        }
        await MainActor.run { [weak self] in
            self?.stat = "Tokens/second: \(String(format: "%.3f", result.tokensPerSecond))"
        }
        return result.output
    }

    
    func cancel() {
        Task { @MainActor in
            running = false
            isProcessing = false
        }
    }
}
