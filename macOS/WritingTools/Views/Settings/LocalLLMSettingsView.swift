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
                platformNotSupportedView
            } else {
                supportedPlatformView
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
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Apple Silicon Required")
                .font(.title)
                .bold()
            
            Text("Local LLM processing is only available on Apple Silicon (M1/M2/M3/M4 etc.) devices.")
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            
            Text("Please select a different AI Provider in the settings if you are on an Intel Mac.")
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
        VStack(alignment: .leading, spacing: 10) {
            // --- Category Filter ---
            Picker("Filter", selection: $selectedModelCategory) {
                ForEach(ModelCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)
            
            // --- Model Selection Picker ---
            VStack(alignment: .leading, spacing: 4) {
                Text("Select Local Model")
                    .font(.headline)
                Picker("Model", selection: $settings.selectedLocalLLMId) {
                    Text("None Selected").tag(String?.none)
                    
                    // Filter models based on selected category
                    ForEach(filteredModels) { modelType in
                        HStack {
                            Text(modelType.displayName)
                            // Optional: Add a camera icon to indicate vision models
                            if modelType.isVisionModel {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .tag(String?.some(modelType.id))
                    }
                }
                .pickerStyle(.menu)
                
                Text("Choose a model to download and use for local processing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let selectedModel = llmProvider.selectedModelType {
                    HStack {
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
            .padding(.bottom, 10)
            
            
            // --- Status/Action Section (only if a model is selected) ---
            if let selectedModelType = llmProvider.selectedModelType {
                GroupBox("Status: \(selectedModelType.displayName)") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Display current status info from provider
                        if !llmProvider.modelInfo.isEmpty {
                            Text(llmProvider.modelInfo)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // --- Action Buttons / Progress ---
                        modelActionView(for: selectedModelType)
                        
                        // Display last error specific to this model
                        if let error = llmProvider.lastError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                // Prompt to select a model
                Text("Please select a model from the dropdown above to see its status and download options.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    // --- Extracted View for Model Actions ---
    @ViewBuilder
    private func modelActionView(for modelType: LocalModelType) -> some View {
        // Show relevant controls based on the provider's state for the selected model
        switch llmProvider.loadState {
        case .idle, .checking:
            ProgressView().controlSize(.small) // Show activity indicator while checking
            Text("Checking status...")
                .foregroundColor(.secondary)
        case .needsDownload:
            HStack {
                Button("Download \(modelType.displayName)") {
                    llmProvider.startDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(llmProvider.isDownloading) // Disable while download starts
                
                // Show retry button only if there was a previous error
                if llmProvider.lastError != nil && llmProvider.retryCount < 3 {
                    Button("Retry Download") {
                        llmProvider.retryDownload()
                    }
                    .disabled(llmProvider.isDownloading)
                }
            }
            
        case .downloaded, .loaded: // Model is ready or loaded
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("\(modelType.displayName) Ready")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Delete Model") {
                    showingDeleteAlert = true // Trigger the alert
                }
                .foregroundColor(.red)
                .disabled(llmProvider.isDownloading || llmProvider.running) // Disable if busy
            }
            if case .loading = llmProvider.loadState {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading model into memory...")
                        .foregroundColor(.secondary)
                }
            }
            
            
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading \(modelType.displayName)...")
                    .foregroundColor(.secondary)
            }
            
        case .error:
            // Error shown separately, provide retry for download errors
            if llmProvider.lastError?.contains("download") == true && llmProvider.retryCount < 3 {
                Button("Retry Download") {
                    llmProvider.retryDownload()
                }
                .disabled(llmProvider.isDownloading)
            } else {
                Text("Cannot proceed due to error.")
                    .foregroundColor(.red)
            }
            
            
        }
        
        // --- Download Progress (shown only when downloading) ---
        if llmProvider.isDownloading {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading \(modelType.displayName)...")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { llmProvider.cancelDownload() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                ProgressView(value: llmProvider.downloadProgress) {
                    Text("\(Int(llmProvider.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .animation(.linear, value: llmProvider.downloadProgress)
            }
        }
    }
}
