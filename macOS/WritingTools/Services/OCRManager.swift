import Foundation
import Vision
import AppKit

class OCRManager {
    static let shared = OCRManager()
    
    private init() {}
    
    // Extracts text from a single image Data object.
    func extractText(from imageData: Data) async -> String {
        await Task.detached {
            guard let nsImage = NSImage(data: imageData),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return "" }
            
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            return await withCheckedContinuation { continuation in
                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try requestHandler.perform([request])
                    guard let observations = request.results else {
                        continuation.resume(returning: "")
                        return
                    }
                    let texts = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }
                    let fullText = texts.joined(separator: "\n")
                    continuation.resume(returning: fullText)
                } catch {
                    continuation.resume(returning: "")
                }
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
