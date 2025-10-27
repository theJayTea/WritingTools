//
//  LocalLLMSettingsView.swift
//  WritingTools
//
//  Created by T3 Chat on 25.07.25.
//

import SwiftUI

struct LocalLLMSettingsView: View {
    @ObservedObject private var llmProvider: LocalModelProvider
    @ObservedObject private var settings = AppSettings.shared
    
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
        self.llmProvider = provider
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !llmProvider.isPlatformSupported {
                GroupBox {
                    platformNotSupportedView
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isHeader)
            } else {
                GroupBox {
                    supportedPlatformView
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // --- Delete Alert ---
        .alert("Delete Model", isPresented: $showingDeleteAlert, presenting: llmProvider.selectedModelType) { modelType in
            Button("Cancel", role: .cancel) { }
            Button("Delete \(modelType.displayName)") {
                Task {
                    do {
                        try llmProvider.deleteModel()
                    } catch {
                        llmProvider.lastError = "Failed to delete \(modelType.displayName): \(error.localizedDescription)"
                    }
                }
            }
        } message: { modelType in
            Text("Are you sure you want to delete the downloaded model \(modelType.displayName)? You'll need to download it again to use it.")
        }
        // --- General Error Alert ---
        .alert("Local LLM Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { llmProvider.lastError = nil }
        } message: {
            Text(llmProvider.lastError ?? "An unknown error occurred.")
        }
        .onChange(of: llmProvider.lastError) { _, newValue in
            // Show the alert if a new error is set by the provider
            if newValue != nil {
                showingErrorAlert = true
            }
        }
    }
    
    private var platformNotSupportedView: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundColor(.red)
                .accessibilityHidden(true)
            
            Text("Apple Silicon Required")
                .font(.title2)
                .bold()
                .accessibilityAddTraits(.isHeader)
            
            Text("Local LLM processing is only available on Apple Silicon (M-series) devices.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Text("Please select a different AI Provider in Settings if you are on an Intel Mac.")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    
    // Filter models based on the selected category
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
    
    private var supportedPlatformView: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Model Filters") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Filter", selection: $selectedModelCategory) {
                        ForEach(ModelCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Filter between all, text-only, and vision-capable models.")
                }
            }

            GroupBox("Model Selection") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a model to download and use for local processing.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Picker("Model", selection: $settings.selectedLocalLLMId) {
                        Text("None Selected").tag(String?.none)
                        ForEach(filteredModels) { modelType in
                            HStack {
                                Text(modelType.displayName)
                                if modelType.isVisionModel {
                                    Image(systemName: "camera.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .tag(String?.some(modelType.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Select a local model. Vision-capable models can process images.")

                    if let selectedModel = llmProvider.selectedModelType {
                        HStack(spacing: 6) {
                            if selectedModel.isVisionModel {
                                Label("Vision-capable model", systemImage: "camera.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text("Can process images directly")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Label("Text-only model", systemImage: "text.justifyleft")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            if let selectedModelType = llmProvider.selectedModelType {
                GroupBox("Status: \(selectedModelType.displayName)") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !llmProvider.modelInfo.isEmpty {
                            Text(llmProvider.modelInfo)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        modelActionView(for: selectedModelType)

                        if let error = llmProvider.lastError {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Error: \(error)")
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Text("Please select a model from the dropdown above to see its status and download options.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func modelActionView(for modelType: LocalModelType) -> some View {
        switch llmProvider.loadState {
        case .idle, .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking status...")
                    .foregroundColor(.secondary)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(modelType.displayName) Ready")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Delete Model") {
                        showingDeleteAlert = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help("Remove the downloaded model from disk.")
                    .disabled(llmProvider.isDownloading || llmProvider.running)
                }

                if case .loading = llmProvider.loadState {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading model into memory...")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Loading model into memory")
                }
            }

        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading \(modelType.displayName)...")
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.red)
            }
        }

        if llmProvider.isDownloading {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading \(modelType.displayName)...")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { llmProvider.cancelDownload() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .accessibilityLabel("Cancel download")
                    }
                    .buttonStyle(.plain)
                    .help("Cancel the current download.")
                }
                ProgressView(value: llmProvider.downloadProgress) {
                    Text("\(Int(llmProvider.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .animation(.linear, value: llmProvider.downloadProgress)
                .accessibilityLabel("Download progress")
            }
        }
    }
}
