import MLX
import MLXLLM
import MLXLMCommon
import MLXRandom
import SwiftUI

// Constants for UserDefaults keys
fileprivate let kModelStatusKey = "local_llm_model_status"
fileprivate let kModelInfoKey = "local_llm_model_info"

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
        LocalLLMProvider.isAppleSilicon
    }
    
    // Use default model from registry.
    //let modelConfiguration : ModelConfiguration = .phi4_mini_instruct_6bit
    let modelConfiguration = ModelRegistry.llama3_2_3B_4bit
    let generateParameters = GenerateParameters(temperature: 0.6)
    let maxTokens = 100000
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
        let idstring = String(describing: modelConfiguration.id)
        let cleanId = idstring.replacingOccurrences(of: "id(\"", with: "")
            .replacingOccurrences(of: "\")", with: "")
        let modelPath = "huggingface/models/\(cleanId)"

        modelDirectory = documentsPath.appendingPathComponent(modelPath)
        
        // Only initialize MLX on Apple Silicon
        if isPlatformSupported {
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
            
            // Load saved state if available
            if let savedModelInfo = UserDefaults.standard.string(forKey: kModelInfoKey) {
                self.modelInfo = savedModelInfo
            }
            
            checkModelStatus()
        } else {
            // Set message for Intel Macs
            modelInfo = "Local LLM is only available on Apple Silicon devices"
            loadState = .idle
            UserDefaults.standard.set(false, forKey: kModelStatusKey)
            UserDefaults.standard.set(modelInfo, forKey: kModelInfoKey)
        }
    }
    
    private func checkModelStatus() {
        guard isPlatformSupported else {
            modelInfo = "Local LLM is only available on Apple Silicon devices"
            return
        }
        
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            let modelFiles = try? FileManager.default.contentsOfDirectory(
                atPath: modelDirectory.path)
            if modelFiles?.isEmpty == false {
                loadState = .idle // Model loads on demand.
                modelInfo = "Model available"
                // Save state
                UserDefaults.standard.set(true, forKey: kModelStatusKey)
                UserDefaults.standard.set(modelInfo, forKey: kModelInfoKey)
            } else {
                loadState = .idle
                modelInfo = "Model needs to be downloaded"
                UserDefaults.standard.set(false, forKey: kModelStatusKey)
                UserDefaults.standard.set(modelInfo, forKey: kModelInfoKey)
            }
        } else {
            loadState = .idle
            modelInfo = "Model needs to be downloaded"
            UserDefaults.standard.set(false, forKey: kModelStatusKey)
            UserDefaults.standard.set(modelInfo, forKey: kModelInfoKey)
        }
    }
    
    func startDownload() {
        guard isPlatformSupported else {
            lastError = "Local LLM is only available on Apple Silicon devices"
            return
        }
        
        guard downloadTask == nil else { return }
        isCancelled = false
        retryCount = 0
        
        downloadTask = Task {
            return try await load()
        }
    }
    
    func cancelDownload() {
        guard isPlatformSupported else { return }
        
        isCancelled = true
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
        modelInfo = "Download cancelled"
        lastError = nil
    }
    
    func retryDownload() {
        guard isPlatformSupported else {
            lastError = "Local LLM is only available on Apple Silicon devices"
            return
        }
        
        guard retryCount < maxRetries else {
            lastError = "Maximum retry attempts reached"
            return
        }
        retryCount += 1
        startDownload()
    }
    
    func deleteModel() throws {
        guard isPlatformSupported else {
            throw NSError(
                domain: "LocalLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Local LLM is only available on Apple Silicon devices"]
            )
        }
        
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
        guard isPlatformSupported else {
            throw NSError(
                domain: "LocalLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Local LLM is only available on Apple Silicon devices"]
            )
        }
        
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
        guard isPlatformSupported else {
            throw NSError(
                domain: "LocalLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Local LLM is only available on Apple Silicon devices"]
            )
        }
        
        if running {
            print("Generation already in progress, waiting for the current process...")
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
