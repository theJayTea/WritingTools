import SwiftUI
import Observation

struct LocalLLMSettingsView: View {
    @Bindable var llmProvider: LocalModelProvider
    @Bindable private var settings = AppSettings.shared

    @State private var showingDeleteAlert = false
    @State private var showingErrorAlert = false
    @State private var selectedModelCategory: ModelCategory = .all

    enum ModelCategory: String, CaseIterable, Identifiable {
        case all = "All Models"
        case text = "Text Models"
        case vision = "Vision Models"

        var id: String { self.rawValue }
    }

    init(provider: LocalModelProvider) {
        _llmProvider = Bindable(wrappedValue: provider)
    }

    var body: some View {
        Group {
            if !llmProvider.isPlatformSupported {
                platformNotSupportedView
            } else {
                supportedPlatformView
            }
        }
        .alert("Delete Model", isPresented: $showingDeleteAlert, presenting: llmProvider.selectedModelType) { modelType in
            Button("Cancel", role: .cancel) { }
            Button("Delete \(modelType.displayName)") {
                Task {
                    do {
                        try await llmProvider.deleteModel()
                    } catch {
                        llmProvider.lastError = "Failed to delete \(modelType.displayName): \(error.localizedDescription)"
                    }
                }
            }
        } message: { modelType in
            Text("Are you sure you want to delete the downloaded model \(modelType.displayName)? You'll need to download it again to use it.")
        }
        .alert("Local LLM Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { llmProvider.lastError = nil }
        } message: {
            Text(llmProvider.lastError ?? "An unknown error occurred.")
        }
        .onChange(of: llmProvider.lastError) { _, newValue in
            if newValue != nil {
                showingErrorAlert = true
            }
        }
    }

    private var platformNotSupportedView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Silicon Required")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("Local LLM processing is only available on Apple Silicon (M-series) devices. Please select a different AI provider.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var supportedPlatformView: some View {
        Group {
            LabeledContent("Filter") {
                Picker("Filter", selection: $selectedModelCategory) {
                    ForEach(ModelCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Filter between all, text-only, and vision-capable models.")
            }

            LabeledContent("Model") {
                Picker("Model", selection: $settings.selectedLocalLLMId) {
                    Text("None Selected").tag(String?.none)
                    ForEach(filteredModels) { modelType in
                        Text(modelType.displayName).tag(String?.some(modelType.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help("Select a local model. Vision-capable models can process images.")
            }

            if let selectedModel = llmProvider.selectedModelType {
                LabeledContent("Capability") {
                    if selectedModel.isVisionModel {
                        Label("Vision-capable", systemImage: "camera.fill")
                            .foregroundStyle(.tint)
                    } else {
                        Label("Text-only", systemImage: "text.justifyleft")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let selectedModelType = llmProvider.selectedModelType {
                if !llmProvider.modelInfo.isEmpty {
                    LabeledContent("Details") {
                        Text(llmProvider.modelInfo)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                LabeledContent("Status") {
                    modelActionView(for: selectedModelType)
                }

                if let error = llmProvider.lastError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error: \(error)")
                }
            } else {
                Text("Select a model above to see its status.")
                    .foregroundStyle(.secondary)
            }

            Button {
                llmProvider.revealModelsFolder()
            } label: {
                Label("Show Models in Finder", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open the folder where local models are stored.")
        }
    }

    private var filteredModels: [LocalModelType] {
        switch selectedModelCategory {
        case .all:
            return LocalModelType.allCases
        case .text:
            return LocalModelType.allCases.filter { !$0.isVisionModel }
        case .vision:
            return LocalModelType.allCases.filter { $0.isVisionModel }
        }
    }

    @ViewBuilder
    private func modelActionView(for modelType: LocalModelType) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            switch llmProvider.loadState {
            case .idle, .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking status...")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Checking model status")

            case .needsDownload:
                HStack(spacing: 8) {
                    Button("Download \(modelType.displayName)") {
                        llmProvider.startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(llmProvider.isDownloading)
                    .help("Download the selected model for offline use.")

                    if llmProvider.lastError != nil && llmProvider.retryCount < 3 {
                        Button("Retry Download") {
                            llmProvider.retryDownload()
                        }
                        .disabled(llmProvider.isDownloading)
                        .buttonStyle(.bordered)
                        .help("Try downloading again if the previous attempt failed.")
                    }
                }

            case .downloaded, .loaded:
                HStack(spacing: 8) {
                    Label("\(modelType.displayName) Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)

                    Button("Delete Model") {
                        showingDeleteAlert = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help("Remove the downloaded model from disk.")
                    .disabled(llmProvider.isDownloading || llmProvider.running)
                }

            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading \(modelType.displayName)...")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Loading model")

            case .error:
                if llmProvider.lastError?.contains("download") == true && llmProvider.retryCount < 3 {
                    Button("Retry Download") {
                        llmProvider.retryDownload()
                    }
                    .disabled(llmProvider.isDownloading)
                    .buttonStyle(.bordered)
                    .help("Try downloading again if the previous attempt failed.")
                } else {
                    Text("Cannot proceed due to error.")
                        .foregroundStyle(.red)
                }
            }

            if llmProvider.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Downloading \(modelType.displayName)...")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { llmProvider.cancelDownload() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Cancel download")
                        }
                        .buttonStyle(.plain)
                        .help("Cancel the current download.")
                    }
                    ProgressView(value: llmProvider.downloadProgress) {
                        Text("\(Int(llmProvider.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .animation(.linear, value: llmProvider.downloadProgress)
                    .accessibilityLabel("Download progress")
                }
                .frame(minWidth: 240)
            }
        }
    }
}
