import Foundation
import CoreML

struct GenerativeEngine {
    private var model: MLModel?

    init() {
        do {
            // Load the local model file (e.g., Phoenix.mlmodelc)
            if let modelURL = Bundle.main.url(forResource: "Phoenix", withExtension: "mlmodelc") {
                model = try MLModel(contentsOf: modelURL)
            }
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    func generateTextWithFoundationModel(prompt: String) async throws -> String {
        guard let model = model else {
            throw NSError(domain: "GenerativeEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        // Prepare the input for the model
        let input = try MLDictionaryFeatureProvider(dictionary: ["prompt": prompt])

        // Perform inference
        if let prediction = try? model.prediction(from: input) as? MLDictionaryFeatureProvider {
            // Extract the generated text from the prediction
            if let generatedText = prediction.featureValue(for: "generatedText")?.stringValue {
                return generatedText
            }
        }

        throw NSError(domain: "GenerativeEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate text"])
    }
}
