import Foundation
import CoreML
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SDError (always compiled)

enum SDError: LocalizedError {
    case notCoreMLModel
    case modelNotDownloaded
    case pipelineNotLoaded
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notCoreMLModel: return "Not a CoreML image generation model."
        case .modelNotDownloaded: return "Model files not found. Please download the model first."
        case .pipelineNotLoaded: return "Stable Diffusion pipeline is not loaded."
        case .unavailable: return "Stable Diffusion is not available in this build."
        }
    }
}

// MARK: - StableDiffusionBackend

#if canImport(StableDiffusion)
import StableDiffusion

// Sendable wrapper: StableDiffusionPipeline is a struct but contains
// reference-type model resources, so we bridge with @unchecked Sendable.
private struct SendablePipeline: @unchecked Sendable {
    let value: StableDiffusionPipeline
}

@MainActor
final class StableDiffusionBackend: ObservableObject {
    static let shared = StableDiffusionBackend()

    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var generationStep = 0
    @Published var generationTotalSteps = 20
    @Published var loadedModelId: String? = nil

    nonisolated(unsafe) private var pipeline: StableDiffusionPipeline?

    private init() {}

    // MARK: - SD Model Directory Helpers

    static func sdBaseDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("sd_models")
    }

    static func sdModelDirectory(for modelId: String) -> URL? {
        sdBaseDirectory()?.appendingPathComponent(modelId)
    }

    static func isCoreMLModelDownloaded(modelId: String) -> Bool {
        guard let dir = sdModelDirectory(for: modelId) else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("_downloaded").path)
    }

    func loadModel(_ model: AIModel) async throws {
        guard model.isCoreMLImageGeneration else { throw SDError.notCoreMLModel }
        guard let dir = StableDiffusionBackend.sdModelDirectory(for: model.id),
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("_downloaded").path)
        else { throw SDError.modelNotDownloaded }

        if loadedModelId == model.id && isLoaded { return }

        isLoading = true
        isLoaded = false
        pipeline = nil
        loadedModelId = nil

        let modelDir = dir

        do {
            let wrapper = try await Self.loadPipeline(from: modelDir)
            pipeline = wrapper.value
            loadedModelId = model.id
            isLoaded = true
        } catch {
            isLoading = false
            throw error
        }
        isLoading = false
    }

    private static func loadPipeline(from modelDir: URL) async throws -> SendablePipeline {
        return try await Task.detached(priority: .userInitiated) {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndGPU
            let p = try StableDiffusionPipeline(
                resourcesAt: modelDir,
                controlNet: [],
                configuration: cfg,
                reduceMemory: true
            )
            try p.loadResources()
            return SendablePipeline(value: p)
        }.value
    }

    func unloadModel() {
        pipeline = nil
        loadedModelId = nil
        isLoaded = false
        isGenerating = false
    }

    func generateImage(
        prompt: String,
        steps: Int,
        seed: UInt32,
        inputImage: CGImage? = nil,
        denoiseStrength: Float = 0.7
    ) async throws -> UIImage? {
        guard let pipeline else { throw SDError.pipelineNotLoaded }

        generationStep = 0
        generationTotalSteps = steps
        isGenerating = true
        defer { isGenerating = false }

        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = "ugly, blurry, bad anatomy, bad quality"
        config.stepCount = steps
        config.seed = seed
        config.guidanceScale = 7.5
        config.schedulerType = .dpmSolverMultistepScheduler
        if let inputImage {
            config.startingImage = inputImage
            config.strength = denoiseStrength
            // mode is a computed property: returns .imageToImage automatically when startingImage is set
        }

        let capturedWrapper = SendablePipeline(value: pipeline)
        let capturedSteps = steps
        let cgImageOrNil = try await Task.detached(priority: .userInitiated) { [weak self] in
            let images = try capturedWrapper.value.generateImages(configuration: config) { [weak self] progress in
                let s = progress.step
                let t = progress.stepCount > 0 ? progress.stepCount : capturedSteps
                Task { @MainActor [weak self] in
                    self?.generationStep = s
                    self?.generationTotalSteps = t
                }
                return !Task.isCancelled
            }
            return images.first.flatMap { $0 }
        }.value

        guard let cgImage = cgImageOrNil else { return nil }
        return UIImage(cgImage: cgImage)
    }

    func cancelGeneration() {
        isGenerating = false
    }
}

#else

// Stub when StableDiffusion package is not yet resolved / not available.
@MainActor
final class StableDiffusionBackend: ObservableObject {
    static let shared = StableDiffusionBackend()

    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var generationStep = 0
    @Published var generationTotalSteps = 20
    @Published var loadedModelId: String? = nil

    private init() {}

    // MARK: - SD Model Directory Helpers

    static func sdBaseDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("sd_models")
    }

    static func sdModelDirectory(for modelId: String) -> URL? {
        sdBaseDirectory()?.appendingPathComponent(modelId)
    }

    static func isCoreMLModelDownloaded(modelId: String) -> Bool {
        guard let dir = sdModelDirectory(for: modelId) else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("_downloaded").path)
    }

    func loadModel(_ model: AIModel) async throws {
        throw SDError.unavailable
    }

    func unloadModel() {}

    func generateImage(
        prompt: String,
        steps: Int,
        seed: UInt32,
        inputImage: CGImage? = nil,
        denoiseStrength: Float = 0.7
    ) async throws -> UIImage? {
        throw SDError.unavailable
    }

    func cancelGeneration() {}
}

#endif
