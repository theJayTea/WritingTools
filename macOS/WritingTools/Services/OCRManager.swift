import Foundation
import Vision
import AppKit

class OCRManager {
    static let shared = OCRManager()
    
    private init() {}
    
    // Extracts text from a single image Data object.
    func extractText(from imageData: Data) async -> String {
        await Task.detached(priority: .userInitiated) {
            guard let nsImage = NSImage(data: imageData),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return "" }
            
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            // Perform the synchronous Vision work on this detached task
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try requestHandler.perform([request])
                guard let observations = request.results else {
                    return ""
                }
                let texts = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                return texts.joined(separator: "\n")
            } catch {
                return ""
            }
        }.value
    }
    
    
    // Extracts text from an array of images.
    func extractText(from images: [Data]) async -> String {
        var combinedText = ""
        for imageData in images {
            let text = await extractText(from: imageData)
            if !text.isEmpty {
                combinedText += text + "\n"
            }
        }
        return combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
