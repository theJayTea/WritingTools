import Foundation
import MLXVLM
import MLXLLM
import MLXLMCommon

enum LocalModelType: String, CaseIterable, Identifiable {
    // LLM Models
    case llama = "llama3_2_3B_4bit"
    case qwen3_4b = "qwen3_4b_4bit"
    case gemma = "gemma_2_2b_it_4bit"
    
    // VLM Models
    case qwen25VL = "qwen2_5vl_3b_instruct_4bit"
    
    var id: String { self.rawValue }
    
    // User-friendly display names
    var displayName: String {
        switch self {
            // LLM Models
        case .llama: return "Llama 3.2 (3B, 4-bit)"
        case .qwen3_4b: return "Qwen 3.0 (4B, 4-bit)"
        case .gemma: return "Gemma 2 IT (2B, 4-bit)"
            
            // VLM Models
        case .qwen25VL: return "Qwen 2.5 VL (3B, 4-bit) 📷"
        }
    }
    
    // Is this a vision-capable model?
    var isVisionModel: Bool {
        switch self {
        case .qwen25VL:
            return true
        default:
            return false
        }
    }
    
    // Corresponding ModelConfiguration from LLMRegistry or VLMRegistry
    var configuration: ModelConfiguration {
        switch self {
            // LLM configurations
        case .llama: return LLMRegistry.llama3_2_3B_4bit
        case .qwen3_4b: return LLMRegistry.qwen3_4b_4bit
        case .gemma: return LLMRegistry.gemma_2_2b_it_4bit
            
            // VLM configurations
        case .qwen25VL: return VLMRegistry.qwen2_5VL3BInstruct4Bit
        }
    }
    
    // Helper to get enum case from configuration ID string
    static func from(id: String?) -> LocalModelType? {
        guard let id = id else { return nil }
        return LocalModelType(rawValue: id)
    }
}
