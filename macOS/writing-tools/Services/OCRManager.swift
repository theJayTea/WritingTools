import Foundation
import Vision
import AppKit

class OCRManager {
 static let shared = OCRManager()
 
 private init() {}
 
 // Extracts text from a single image Data object.
 func extractText(from imageData: Data) async -> String {
     guard let nsImage = NSImage(data: imageData),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
     else { return "" }
     
     let request = VNRecognizeTextRequest()
     request.recognitionLevel = .accurate
     request.usesLanguageCorrection = true
     // Optionally you can set supported languages:

     // request.recognitionLanguages = ["en"]
     
     return await withCheckedContinuation { continuation in
         let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
         do {
             try requestHandler.perform([request])
             if let observations = request.results as? [VNRecognizedTextObservation] {
                 let texts = observations.compactMap { observation in
                     observation.topCandidates(1).first?.string
                 }
                 let fullText = texts.joined(separator: "\n")
                 continuation.resume(returning: fullText)
             } else {
                 continuation.resume(returning: "")
             }
         } catch {
             continuation.resume(returning: "")
         }
     }
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
