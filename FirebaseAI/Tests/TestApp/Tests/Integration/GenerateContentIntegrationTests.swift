// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import FirebaseAI
import FirebaseAITestApp
import FirebaseAuth
import FirebaseCore
import FirebaseStorage
import Testing

#if canImport(UIKit)
  import UIKit
#endif // canImport(UIKit)

@testable import struct FirebaseAI.BackendError

@Suite(.serialized)
struct GenerateContentIntegrationTests {
  // Set temperature, topP and topK to lowest allowed values to make responses more deterministic.
  let generationConfig = GenerationConfig(temperature: 0.0, topP: 0.0, topK: 1)
  let safetySettings = [
    SafetySetting(harmCategory: .harassment, threshold: .blockLowAndAbove),
    SafetySetting(harmCategory: .hateSpeech, threshold: .blockLowAndAbove),
    SafetySetting(harmCategory: .sexuallyExplicit, threshold: .blockLowAndAbove),
    SafetySetting(harmCategory: .dangerousContent, threshold: .blockLowAndAbove),
    SafetySetting(harmCategory: .civicIntegrity, threshold: .blockLowAndAbove),
  ]
  // Candidates and total token counts may differ slightly between runs due to whitespace tokens.
  let tokenCountAccuracy = 1

  let storage: Storage
  let userID1: String

  init() async throws {
    userID1 = try await TestHelpers.getUserID()
    storage = Storage.storage()
  }

  @Test(arguments: [
    (InstanceConfig.vertexAI_v1beta, ModelNames.gemini2FlashLite),
    (InstanceConfig.vertexAI_v1beta_global, ModelNames.gemini2FlashLite),
    (InstanceConfig.vertexAI_v1beta_staging, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemma3_4B),
    (InstanceConfig.googleAI_v1beta_staging, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta_staging, ModelNames.gemma3_4B),
    (InstanceConfig.googleAI_v1beta_freeTier_bypassProxy, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta_freeTier_bypassProxy, ModelNames.gemma3_4B),
  ])
  func generateContent(_ config: InstanceConfig, modelName: String) async throws {
    let model = FirebaseAI.componentInstance(config).generativeModel(
      modelName: modelName,
      generationConfig: generationConfig,
      safetySettings: safetySettings,
    )
    let prompt = "Where is Google headquarters located? Answer with the city name only."

    let response = try await model.generateContent(prompt)

    let text = try #require(response.text).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "Mountain View")

    let usageMetadata = try #require(response.usageMetadata)
    #expect(usageMetadata.promptTokenCount.isEqual(to: 13, accuracy: tokenCountAccuracy))
    #expect(usageMetadata.promptTokensDetails.count == 1)
    let promptTokensDetails = try #require(usageMetadata.promptTokensDetails.first)
    #expect(promptTokensDetails.modality == .text)
    #expect(promptTokensDetails.tokenCount == usageMetadata.promptTokenCount)
    #expect(usageMetadata.thoughtsTokenCount == 0)
    // The fields `candidatesTokenCount` and `candidatesTokensDetails` are not included when using
    // Gemma models.
    if modelName.hasPrefix("gemma") {
      #expect(usageMetadata.candidatesTokenCount == 0)
      #expect(usageMetadata.candidatesTokensDetails.isEmpty)
    } else {
      #expect(usageMetadata.candidatesTokenCount.isEqual(to: 3, accuracy: tokenCountAccuracy))
      #expect(usageMetadata.candidatesTokensDetails.count == 1)
      let candidatesTokensDetails = try #require(usageMetadata.candidatesTokensDetails.first)
      #expect(candidatesTokensDetails.modality == .text)
      #expect(candidatesTokensDetails.tokenCount == usageMetadata.candidatesTokenCount)
    }
    #expect(usageMetadata.totalTokenCount > 0)
    #expect(usageMetadata.totalTokenCount ==
      (usageMetadata.promptTokenCount + usageMetadata.candidatesTokenCount))
  }

  @Test(
    "Generate an enum and provide a system instruction",
    arguments: InstanceConfig.allConfigs
  )
  func generateContentEnum(_ config: InstanceConfig) async throws {
    let model = FirebaseAI.componentInstance(config).generativeModel(
      modelName: ModelNames.gemini2FlashLite,
      generationConfig: GenerationConfig(
        responseMIMEType: "text/x.enum",
        responseSchema: .enumeration(values: ["Red", "Green", "Blue"])
      ),
      safetySettings: safetySettings,
      tools: [],
      toolConfig: .init(functionCallingConfig: .none()),
      systemInstruction: ModelContent(role: "system", parts: "Always pick blue.")
    )
    let prompt = "What is your favourite colour?"

    let response = try await model.generateContent(prompt)

    let text = try #require(response.text).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "Blue")

    let usageMetadata = try #require(response.usageMetadata)
    #expect(usageMetadata.promptTokenCount.isEqual(to: 15, accuracy: tokenCountAccuracy))
    #expect(usageMetadata.candidatesTokenCount.isEqual(to: 1, accuracy: tokenCountAccuracy))
    #expect(usageMetadata.thoughtsTokenCount == 0)
    #expect(usageMetadata.totalTokenCount
      == usageMetadata.promptTokenCount + usageMetadata.candidatesTokenCount)
    #expect(usageMetadata.promptTokensDetails.count == 1)
    let promptTokensDetails = try #require(usageMetadata.promptTokensDetails.first)
    #expect(promptTokensDetails.modality == .text)
    #expect(promptTokensDetails.tokenCount == usageMetadata.promptTokenCount)
    #expect(usageMetadata.candidatesTokensDetails.count == 1)
    let candidatesTokensDetails = try #require(usageMetadata.candidatesTokensDetails.first)
    #expect(candidatesTokensDetails.modality == .text)
    #expect(candidatesTokensDetails.tokenCount == usageMetadata.candidatesTokenCount)
  }

  @Test(arguments: [
    (InstanceConfig.vertexAI_v1beta, ModelNames.gemini2_5_Flash, 0),
    (InstanceConfig.vertexAI_v1beta, ModelNames.gemini2_5_Flash, 24576),
    (InstanceConfig.vertexAI_v1beta_global, ModelNames.gemini2_5_Pro, 128),
    (InstanceConfig.vertexAI_v1beta_global, ModelNames.gemini2_5_Pro, 32768),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemini2_5_Flash, 0),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemini2_5_Flash, 24576),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemini2_5_Pro, 128),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemini2_5_Pro, 32768),
    (InstanceConfig.googleAI_v1beta_freeTier, ModelNames.gemini2_5_Flash, 0),
    (InstanceConfig.googleAI_v1beta_freeTier, ModelNames.gemini2_5_Flash, 24576),
  ])
  func generateContentThinking(_ config: InstanceConfig, modelName: String,
                               thinkingBudget: Int) async throws {
    let model = FirebaseAI.componentInstance(config).generativeModel(
      modelName: modelName,
      generationConfig: GenerationConfig(
        temperature: 0.0,
        topP: 0.0,
        topK: 1,
        thinkingConfig: ThinkingConfig(thinkingBudget: thinkingBudget)
      ),
      safetySettings: safetySettings
    )
    let prompt = "Where is Google headquarters located? Answer with the city name only."

    let response = try await model.generateContent(prompt)

    let text = try #require(response.text).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "Mountain View")

    let usageMetadata = try #require(response.usageMetadata)
    #expect(usageMetadata.promptTokenCount.isEqual(to: 13, accuracy: tokenCountAccuracy))
    #expect(usageMetadata.promptTokensDetails.count == 1)
    let promptTokensDetails = try #require(usageMetadata.promptTokensDetails.first)
    #expect(promptTokensDetails.modality == .text)
    #expect(promptTokensDetails.tokenCount == usageMetadata.promptTokenCount)
    if thinkingBudget == 0 {
      #expect(usageMetadata.thoughtsTokenCount == 0)
    } else {
      #expect(usageMetadata.thoughtsTokenCount <= thinkingBudget)
    }
    #expect(usageMetadata.candidatesTokenCount.isEqual(to: 3, accuracy: tokenCountAccuracy))
    // The `candidatesTokensDetails` field is erroneously omitted when using the Google AI (Gemini
    // Developer API) backend.
    if case .googleAI = config.apiConfig.service {
      #expect(usageMetadata.candidatesTokensDetails.isEmpty)
    } else {
      #expect(usageMetadata.candidatesTokensDetails.count == 1)
      let candidatesTokensDetails = try #require(usageMetadata.candidatesTokensDetails.first)
      #expect(candidatesTokensDetails.modality == .text)
      #expect(candidatesTokensDetails.tokenCount == usageMetadata.candidatesTokenCount)
    }
    #expect(usageMetadata.totalTokenCount > 0)
    #expect(usageMetadata.totalTokenCount == (
      usageMetadata.promptTokenCount
        + usageMetadata.thoughtsTokenCount
        + usageMetadata.candidatesTokenCount
    ))
  }

  @Test(arguments: [
    InstanceConfig.vertexAI_v1beta,
    InstanceConfig.vertexAI_v1beta_global,
    InstanceConfig.googleAI_v1beta,
    InstanceConfig.googleAI_v1beta_staging,
    InstanceConfig.googleAI_v1beta_freeTier_bypassProxy,
  ])
  func generateImage(_ config: InstanceConfig) async throws {
    let generationConfig = GenerationConfig(
      temperature: 0.0,
      topP: 0.0,
      topK: 1,
      responseModalities: [.text, .image]
    )
    let safetySettings = safetySettings.filter {
      // HARM_CATEGORY_CIVIC_INTEGRITY is deprecated in Vertex AI but only rejected when using the
      // 'gemini-2.0-flash-preview-image-generation' model.
      $0.harmCategory != .civicIntegrity
    }
    let model = FirebaseAI.componentInstance(config).generativeModel(
      modelName: ModelNames.gemini2FlashPreviewImageGeneration,
      generationConfig: generationConfig,
      safetySettings: safetySettings
    )
    let prompt = "Generate an image of a cute cartoon kitten playing with a ball of yarn."

    var response: GenerateContentResponse?
    try await withKnownIssue(
      "Backend may fail with a 503 - Service Unavailable error when overloaded",
      isIntermittent: true
    ) {
      response = try await model.generateContent(prompt)
    } matching: { issue in
      (issue.error as? BackendError).map { $0.httpResponseCode == 503 } ?? false
    }

    guard let response else { return }
    let candidate = try #require(response.candidates.first)
    let inlineDataPart = try #require(candidate.content.parts
      .first { $0 is InlineDataPart } as? InlineDataPart)
    let inlineDataPartsViaAccessor = response.inlineDataParts
    #expect(inlineDataPartsViaAccessor.count == 1)
    let inlineDataPartViaAccessor = try #require(inlineDataPartsViaAccessor.first)
    #expect(inlineDataPart == inlineDataPartViaAccessor)
    #expect(inlineDataPart.mimeType == "image/png")
    #expect(inlineDataPart.data.count > 0)
    #if canImport(UIKit)
      let uiImage = try #require(UIImage(data: inlineDataPart.data))
      // Gemini 2.0 Flash Experimental returns images sized to fit within a 1024x1024 pixel box but
      // dimensions may vary depending on the aspect ratio.
      #expect(uiImage.size.width <= 1024)
      #expect(uiImage.size.width >= 500)
      #expect(uiImage.size.height <= 1024)
      #expect(uiImage.size.height >= 500)
    #endif // canImport(UIKit)
  }

  @Test(
    "generateContent with Google Search returns grounding metadata",
    arguments: InstanceConfig.allConfigs
  )
  func generateContent_withGoogleSearch_succeeds(_ config: InstanceConfig) async throws {
    let model = FirebaseAI.componentInstance(config).generativeModel(
      modelName: ModelNames.gemini2Flash,
      tools: [.googleSearch()]
    )
    let prompt = "What is the weather in Toronto today?"

    let response = try await model.generateContent(prompt)

    let candidate = try #require(response.candidates.first)
    let groundingMetadata = try #require(candidate.groundingMetadata)
    let searchEntrypoint = try #require(groundingMetadata.searchEntryPoint)

    #expect(!groundingMetadata.webSearchQueries.isEmpty)
    #expect(!searchEntrypoint.renderedContent.isEmpty)
    #expect(!groundingMetadata.groundingChunks.isEmpty)
    #expect(!groundingMetadata.groundingSupports.isEmpty)

    for chunk in groundingMetadata.groundingChunks {
      #expect(chunk.web != nil)
    }

    for support in groundingMetadata.groundingSupports {
      let segment = support.segment
      #expect(segment.endIndex > segment.startIndex)
      #expect(!segment.text.isEmpty)
      #expect(!support.groundingChunkIndices.isEmpty)

      // Ensure indices point to valid chunks
      for index in support.groundingChunkIndices {
        #expect(index < groundingMetadata.groundingChunks.count)
      }
    }
  }

  // MARK: Streaming Tests

  @Test(arguments: [
    (InstanceConfig.vertexAI_v1beta, ModelNames.gemini2FlashLite),
    (InstanceConfig.vertexAI_v1beta_global, ModelNames.gemini2FlashLite),
    (InstanceConfig.vertexAI_v1beta_staging, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta, ModelNames.gemma3_4B),
    (InstanceConfig.googleAI_v1beta_staging, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta_staging, ModelNames.gemma3_4B),
    (InstanceConfig.googleAI_v1beta_freeTier_bypassProxy, ModelNames.gemini2FlashLite),
    (InstanceConfig.googleAI_v1beta_freeTier_bypassProxy, ModelNames.gemma3_4B),
  ])
  func generateContentStream(_ config: InstanceConfig, modelName: String) async throws {
    let expectedResponse = [
      "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune",
    ]
    let prompt = """
    Generate a JSON array of strings. The array must contain the names of the planets in Earth's \
    solar system, ordered from closest to furthest from the Sun.

    Constraints:
    - Output MUST be only the JSON array.
    - Do NOT include any introductory or explanatory text.
    - Do NOT wrap the JSON in Markdown code blocks (e.g., ```json ... ``` or ``` ... ```).
    - The response must start with '[' and end with ']'.
    """
    let model = FirebaseAI.componentInstance(config).generativeModel(
      modelName: modelName,
      generationConfig: generationConfig,
      safetySettings: safetySettings
    )
    let chat = model.startChat()

    let stream = try chat.sendMessageStream(prompt)
    var textValues = [String]()
    for try await value in stream {
      if let text = value.text {
        textValues.append(text)
      } else if let finishReason = value.candidates.first?.finishReason {
        #expect(finishReason == .stop)
      } else {
        Issue.record("Expected a candidate with a `TextPart` or a `finishReason`; got \(value).")
      }
    }

    let userHistory = try #require(chat.history.first)
    #expect(userHistory.role == "user")
    #expect(userHistory.parts.count == 1)
    let promptTextPart = try #require(userHistory.parts.first as? TextPart)
    #expect(promptTextPart.text == prompt)
    let modelHistory = try #require(chat.history.last)
    #expect(modelHistory.role == "model")
    #expect(modelHistory.parts.count == 1)
    let modelTextPart = try #require(modelHistory.parts.first as? TextPart)
    let modelJSONData = try #require(modelTextPart.text.data(using: .utf8))
    let response = try JSONDecoder().decode([String].self, from: modelJSONData)
    #expect(response == expectedResponse)
  }

  // MARK: - App Check Tests

  @Test(arguments: InstanceConfig.appCheckNotConfiguredConfigs)
  func generateContent_appCheckNotConfigured_shouldFail(_ config: InstanceConfig) async throws {
    let model = FirebaseAI.componentInstance(config).generativeModel(
      modelName: ModelNames.gemini2Flash
    )
    let prompt = "Where is Google headquarters located? Answer with the city name only."

    try await #require {
      _ = try await model.generateContent(prompt)
    } throws: {
      guard let error = $0 as? GenerateContentError else {
        Issue.record("Expected a \(GenerateContentError.self); got \($0.self).")
        return false
      }
      guard case let .internalError(underlyingError) = error else {
        Issue.record("Expected a GenerateContentError.internalError(...); got \(error.self).")
        return false
      }

      return String(describing: underlyingError).contains("Firebase App Check token is invalid")
    }
  }
}
