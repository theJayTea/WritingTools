import Foundation
import MLXLMCommon

// This struct defines a simple configuration for an MLX LLM.

extension ModelConfiguration {

    public static func == (lhs: MLXLMCommon.ModelConfiguration, rhs: MLXLMCommon.ModelConfiguration) -> Bool {
           return lhs.name == rhs.name
       }
    // New configuration for Mistral Small 24B.
    // This uses the repository provided: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit"
    public static let mistralSmall24B = ModelConfiguration(
        id: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit"
    )
    
    public static let qwen2_5_7b_1M_4bit = ModelConfiguration(
        id: "mlx-community/Qwen2.5-7B-Instruct-1M-4bit"
    )
    
    public static let qwen2_5_3b_4bit = ModelConfiguration(
        id: "mlx-community/Qwen2.5-3B-Instruct-4bit"
    )
    
    public static let deepseek_r1_qwen_14b_4bit = ModelConfiguration(
        id: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
    )
    
    public static let phi4_mini_instruct_4bit = ModelConfiguration(
        id: "mlx-community/Phi-4-mini-instruct-4bit"
    )
    
    public static let teuken_7B_4bit = ModelConfiguration(
        id: "stelterlab/Teuken-7B-instruct-commercial-v0.4-MLX-4bit"
    )
    
    public static let gemma3_4B_it_4bit = ModelConfiguration(
        id: "mlx-community/gemma-3-text-4b-it-4bit"
    )
    
}
