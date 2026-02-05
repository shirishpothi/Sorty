//
//  CostCalculator.swift
//  Sorty
//
//  Utility for estimating API costs based on token usage
//

import Foundation

public enum CostCalculator {
    /// Pricing per 1,000,000 tokens in USD
    struct ModelPricing {
        let inputPrice: Decimal
        let outputPrice: Decimal
    }
    
    private static let pricingMap: [String: ModelPricing] = [
        // OpenAI
        "gpt-4o": ModelPricing(inputPrice: 5.00, outputPrice: 15.00),
        "gpt-4o-mini": ModelPricing(inputPrice: 0.15, outputPrice: 0.60),
        "gpt-4-turbo": ModelPricing(inputPrice: 10.00, outputPrice: 30.00),
        "gpt-3.5-turbo": ModelPricing(inputPrice: 0.50, outputPrice: 1.50),
        
        // Anthropic
        "claude-3-5-sonnet": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-3-opus": ModelPricing(inputPrice: 15.00, outputPrice: 75.00),
        "claude-3-haiku": ModelPricing(inputPrice: 0.25, outputPrice: 1.25),
        
        // Google
        "gemini-1.5-pro": ModelPricing(inputPrice: 3.50, outputPrice: 10.50),
        "gemini-1.5-flash": ModelPricing(inputPrice: 0.075, outputPrice: 0.30),
        
        // Groq / Llama (Rough estimation)
        "llama3-70b": ModelPricing(inputPrice: 0.59, outputPrice: 0.79),
        "llama3-8b": ModelPricing(inputPrice: 0.05, outputPrice: 0.10)
    ]
    
    /// Fallback pricing for unknown models (conservative estimate)
    private static let baselinePricing = ModelPricing(inputPrice: 1.00, outputPrice: 2.00)
    
    /// Calculate estimated cost in USD
    public static func calculate(model: String, inputTokens: Int, outputTokens: Int) -> Decimal {
        let pricing = pricingMap.first { model.lowercased().contains($0.key) }?.value ?? baselinePricing
        
        let inputCost = (Decimal(inputTokens) / 1_000_000) * pricing.inputPrice
        let outputCost = (Decimal(outputTokens) / 1_000_000) * pricing.outputPrice
        
        return inputCost + outputCost
    }
}
