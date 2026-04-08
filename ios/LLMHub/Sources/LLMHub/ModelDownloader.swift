import Foundation
import ZIPFoundation

private extension URLError.Code {
    var isTransientDownloadFailure: Bool {
        switch self {
        case .networkConnectionLost,
            .notConnectedToInternet,
            .timedOut,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .resourceUnavailable,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}

public struct DownloadUpdate: Sendable {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let speedBytesPerSecond: Double
}

public actor ModelDownloader {
    public static let shared = ModelDownloader()
    
    private let urlSession: URLSession
    private let completionThresholdRatio: Double = 0.98
    private let optionalModelFiles: Set<String> = []
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // 1 hour for large models
        self.urlSession = URLSession(configuration: config)
    }

    private func remoteFileSize(fileURL: URL, hfToken: String?) async -> Int64? {
        func authorizedRequest(method: String) -> URLRequest {
            var request = URLRequest(url: fileURL, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = method
            if let token = hfToken, !token.isEmpty {
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        // First try HEAD for content length.
        do {
            let request = authorizedRequest(method: "HEAD")
            let (_, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let size = Int64(contentLength),
               size > 0 {
                return size
            }
        } catch {
            // Fall through to range probe.
        }

        // Some endpoints block HEAD; probe with GET Range to parse total size from Content-Range.
        do {
            var request = authorizedRequest(method: "GET")
            request.addValue("bytes=0-0", forHTTPHeaderField: "Range")
            let (_, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if let total = totalSizeFromContentRange(httpResponse.value(forHTTPHeaderField: "Content-Range")), total > 0 {
                    return total
                }
                if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                   let size = Int64(contentLength),
                   size > 0,
                   httpResponse.statusCode == 200 {
                    return size
                }
            }
        } catch {
            // Give up and treat as unknown size.
        }
        return nil
    }

    private func localFileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileSize = attrs[.size] as? Int64
        else {
            return 0
        }
        return max(0, fileSize)
    }

    private func totalSizeFromContentRange(_ contentRange: String?) -> Int64? {
        guard let contentRange else { return nil }
        // 416 responses often include: "bytes */123456"
        guard let slash = contentRange.lastIndex(of: "/") else { return nil }
        let tail = contentRange[contentRange.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        guard tail != "*", let value = Int64(tail), value > 0 else { return nil }
        return value
    }
    
    public func downloadModel(
        _ model: AIModel,
        hfToken: String?,
        destinationDir: URL,
        onProgress: @Sendable @escaping (DownloadUpdate) -> Void
    ) async throws {
        // CoreML models (Stable Diffusion) are distributed as ZIP archives;
        // download, extract, and store a sentinel to mark completion.
        if model.modelFormat == .coreml {
            try await downloadAndExtractCoreML(
                model: model,
                hfToken: hfToken,
                destinationDir: destinationDir,
                onProgress: onProgress
            )
            return
        }
        let totalSize = model.sizeBytes
        var downloadedBytesPerFile: [String: Int64] = [:]
        var expectedBytesPerFile: [String: Int64] = [:]
        let realtimeWindowSeconds: TimeInterval = 3.0
        var throughputSamples: [(time: Date, bytes: Int64)] = []

        func recordTransfer(_ bytes: Int64) {
            guard bytes > 0 else { return }
            let now = Date()
            throughputSamples.append((time: now, bytes: bytes))
            let cutoff = now.addingTimeInterval(-realtimeWindowSeconds)
            throughputSamples.removeAll { $0.time < cutoff }
        }

        func realtimeSpeed() -> Double {
            guard !throughputSamples.isEmpty else { return 0 }
            let now = Date()
            let cutoff = now.addingTimeInterval(-realtimeWindowSeconds)
            throughputSamples.removeAll { $0.time < cutoff }
            guard let firstTime = throughputSamples.first?.time else { return 0 }
            let bytes = throughputSamples.reduce(Int64(0)) { $0 + $1.bytes }
            let span = max(0.1, now.timeIntervalSince(firstTime))
            return Double(bytes) / span
        }
        
        // Ensure clean destination
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        
        let downloadItems = Array(zip(model.requiredFileNames, model.allDownloadURLs))

        for (fileName, fileURL) in downloadItems {
            
            let destinationFileURL = destinationDir.appendingPathComponent(fileName)
            let expectedSize = await remoteFileSize(fileURL: fileURL, hfToken: hfToken)
            if let expectedSize {
                expectedBytesPerFile[fileName] = expectedSize
            }
            
            // Check if file exists and is already downloaded fully.
            // We only skip when local size matches remote Content-Length.
            if FileManager.default.fileExists(atPath: destinationFileURL.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationFileURL.path),
                   let fileSize = attrs[.size] as? Int64,
                   fileSize > 0 {
                    if let expectedSize, expectedSize == fileSize {
                        downloadedBytesPerFile[fileName] = fileSize
                        let currentTotal = downloadedBytesPerFile.values.reduce(0, +)
                        let speed = realtimeSpeed()
                        onProgress(DownloadUpdate(bytesDownloaded: currentTotal, totalBytes: totalSize, speedBytesPerSecond: speed))
                        continue
                    }
                }
            }
            
            let maxRetries = 6
            var attempt = 0
            var finishedFile = false
            var restartedAfter416 = false

            while !finishedFile {
                do {
                    var existingBytes = localFileSize(at: destinationFileURL)
                    var request = URLRequest(url: fileURL, cachePolicy: .reloadIgnoringLocalCacheData)
                    if let token = hfToken, !token.isEmpty {
                        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    if existingBytes > 0 {
                        request.addValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
                    }

                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "ModelDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Response"])
                    }

                    // Critical 404/403 Handling
                    if !(200...299).contains(httpResponse.statusCode) {
                        if httpResponse.statusCode == 416 {
                            let rangeHeaderTotal = totalSizeFromContentRange(httpResponse.value(forHTTPHeaderField: "Content-Range"))
                            let refreshedExpected: Int64?
                            if let expectedSize {
                                refreshedExpected = expectedSize
                            } else if let rangeHeaderTotal {
                                refreshedExpected = rangeHeaderTotal
                            } else {
                                refreshedExpected = await remoteFileSize(fileURL: fileURL, hfToken: hfToken)
                            }
                            if let refreshedExpected, existingBytes >= refreshedExpected {
                                downloadedBytesPerFile[fileName] = refreshedExpected
                                let currentTotal = downloadedBytesPerFile.values.reduce(0, +)
                                let speed = realtimeSpeed()
                                onProgress(DownloadUpdate(bytesDownloaded: currentTotal, totalBytes: totalSize, speedBytesPerSecond: speed))
                                finishedFile = true
                                break
                            }

                            // Range is invalid for current server file length; restart this file once from zero.
                            if !restartedAfter416 {
                                try? FileManager.default.removeItem(at: destinationFileURL)
                                downloadedBytesPerFile[fileName] = 0
                                restartedAfter416 = true
                                continue
                            }
                        }

                        // Ignore missing optional files.
                        if httpResponse.statusCode == 404 && optionalModelFiles.contains(fileName) {
                            finishedFile = true
                            break
                        }

                        let reason = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                        throw NSError(domain: "ModelDownloader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(reason)"])
                    }

                    // Efficient Buffered Write with resume support.
                    // 206 means server accepted Range and we should append.
                    // 200 means full content, so restart file from zero.
                    if !FileManager.default.fileExists(atPath: destinationFileURL.path) {
                        FileManager.default.createFile(atPath: destinationFileURL.path, contents: nil)
                    }
                    if existingBytes > 0 && httpResponse.statusCode == 200 {
                        try? FileManager.default.removeItem(at: destinationFileURL)
                        FileManager.default.createFile(atPath: destinationFileURL.path, contents: nil)
                        existingBytes = 0
                    }
                    let fileHandle = try FileHandle(forWritingTo: destinationFileURL)
                    defer { try? fileHandle.close() }
                    if existingBytes > 0 {
                        try fileHandle.seekToEnd()
                    } else {
                        try fileHandle.truncate(atOffset: 0)
                    }

                    var byteCountPerFile: Int64 = existingBytes
                    var buffer = Data()
                    let chunkSize = 64 * 1024 // 64KB buffer

                    for try await byte in bytes {
                        buffer.append(byte)
                        byteCountPerFile += 1

                        if buffer.count >= chunkSize {
                            let flushedBytes = Int64(buffer.count)
                            try fileHandle.write(contentsOf: buffer)
                            buffer.removeAll(keepingCapacity: true)
                            recordTransfer(flushedBytes)

                            // Periodic Progress Update
                            downloadedBytesPerFile[fileName] = byteCountPerFile
                            let currentTotal = downloadedBytesPerFile.values.reduce(0, +)
                            let speed = realtimeSpeed()
                            onProgress(DownloadUpdate(bytesDownloaded: currentTotal, totalBytes: totalSize, speedBytesPerSecond: speed))
                        }
                    }

                    if !buffer.isEmpty {
                        let flushedBytes = Int64(buffer.count)
                        try fileHandle.write(contentsOf: buffer)
                        buffer.removeAll()
                        recordTransfer(flushedBytes)
                    }

                    downloadedBytesPerFile[fileName] = byteCountPerFile
                    let currentTotal = downloadedBytesPerFile.values.reduce(0, +)
                    let speed = realtimeSpeed()
                    onProgress(DownloadUpdate(bytesDownloaded: currentTotal, totalBytes: totalSize, speedBytesPerSecond: speed))
                    finishedFile = true
                } catch let error as URLError where error.code.isTransientDownloadFailure && attempt < maxRetries {
                    attempt += 1
                    let delaySeconds = min(pow(2.0, Double(attempt - 1)), 30.0)
                    try await Task.sleep(for: .seconds(delaySeconds))
                }
            }
        }

        var finalBytes: Int64 = 0
        for fileName in model.requiredFileNames {
            if optionalModelFiles.contains(fileName) {
                continue
            }

            let localURL = destinationDir.appendingPathComponent(fileName)
            let localBytes = localFileSize(at: localURL)
            finalBytes += localBytes

            if let expectedBytes = expectedBytesPerFile[fileName], expectedBytes > 0 {
                if localBytes != expectedBytes {
                    throw NSError(
                        domain: "ModelDownloader",
                        code: -2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Incomplete file: \(fileName) (\(localBytes) / \(expectedBytes) bytes)"
                        ]
                    )
                }
            } else if localBytes <= 0 {
                throw NSError(
                    domain: "ModelDownloader",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Missing downloaded file: \(fileName)"
                    ]
                )
            }
        }

        let minimumExpectedBytes = Int64(Double(totalSize) * completionThresholdRatio)
        if finalBytes < minimumExpectedBytes {
            // Keep this guard as a soft sanity check for metadata-based progress,
            // but by this point each file has already been validated above.
            onProgress(DownloadUpdate(bytesDownloaded: finalBytes, totalBytes: totalSize, speedBytesPerSecond: 0))
        }
    }

    // MARK: - CoreML ZIP Download + Extraction

    private func downloadAndExtractCoreML(
        model: AIModel,
        hfToken: String?,
        destinationDir: URL,
        onProgress: @Sendable @escaping (DownloadUpdate) -> Void
    ) async throws {
        guard let zipURL = model.allDownloadURLs.first else {
            throw NSError(domain: "ModelDownloader", code: -4, userInfo: [NSLocalizedDescriptionKey: "No download URL for CoreML model"])
        }

        let totalSize = model.sizeBytes
        let sentinelURL = destinationDir.appendingPathComponent("_downloaded")

        // Already extracted
        if FileManager.default.fileExists(atPath: sentinelURL.path) {
            onProgress(DownloadUpdate(bytesDownloaded: totalSize, totalBytes: totalSize, speedBytesPerSecond: 0))
            return
        }

        if !FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        let tempZipURL = destinationDir.appendingPathComponent("_temp_download.zip")

        // Download the ZIP with resume support
        let realtimeWindowSeconds: TimeInterval = 3.0
        var throughputSamples: [(time: Date, bytes: Int64)] = []
        func recordTransfer(_ bytes: Int64) {
            let now = Date()
            throughputSamples.append((time: now, bytes: bytes))
            let cutoff = now.addingTimeInterval(-realtimeWindowSeconds)
            throughputSamples.removeAll { $0.time < cutoff }
        }
        func realtimeSpeed() -> Double {
            let now = Date()
            let cutoff = now.addingTimeInterval(-realtimeWindowSeconds)
            throughputSamples.removeAll { $0.time < cutoff }
            guard let firstTime = throughputSamples.first?.time else { return 0 }
            let bytes = throughputSamples.reduce(Int64(0)) { $0 + $1.bytes }
            let span = max(0.1, now.timeIntervalSince(firstTime))
            return Double(bytes) / span
        }

        let maxRetries = 6
        var attempt = 0
        var downloadComplete = false
        var downloadedBytes: Int64 = 0

        while !downloadComplete {
            do {
                var existingBytes = localFileSize(at: tempZipURL)
                var request = URLRequest(url: zipURL, cachePolicy: .reloadIgnoringLocalCacheData)
                if let token = hfToken, !token.isEmpty {
                    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                if existingBytes > 0 {
                    request.addValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
                }

                let (bytes, response) = try await urlSession.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "ModelDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
                }

                if !(200...299).contains(httpResponse.statusCode) {
                    if httpResponse.statusCode == 416 {
                        // Already complete
                        existingBytes = localFileSize(at: tempZipURL)
                        downloadedBytes = existingBytes
                        onProgress(DownloadUpdate(bytesDownloaded: existingBytes, totalBytes: totalSize, speedBytesPerSecond: 0))
                        downloadComplete = true
                        break
                    }
                    let reason = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    throw NSError(domain: "ModelDownloader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(reason)"])
                }

                if !FileManager.default.fileExists(atPath: tempZipURL.path) {
                    FileManager.default.createFile(atPath: tempZipURL.path, contents: nil)
                }
                if existingBytes > 0 && httpResponse.statusCode == 200 {
                    try? FileManager.default.removeItem(at: tempZipURL)
                    FileManager.default.createFile(atPath: tempZipURL.path, contents: nil)
                    existingBytes = 0
                }
                let fileHandle = try FileHandle(forWritingTo: tempZipURL)
                defer { try? fileHandle.close() }
                if existingBytes > 0 {
                    try fileHandle.seekToEnd()
                } else {
                    try fileHandle.truncate(atOffset: 0)
                }

                var byteCount: Int64 = existingBytes
                var buffer = Data()
                let chunkSize = 64 * 1024

                for try await byte in bytes {
                    buffer.append(byte)
                    byteCount += 1
                    if buffer.count >= chunkSize {
                        let flushed = Int64(buffer.count)
                        try fileHandle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)
                        recordTransfer(flushed)
                        downloadedBytes = byteCount
                        // Report 90% of progress for the download phase
                        let reportedBytes = Int64(Double(byteCount) * 0.9)
                        onProgress(DownloadUpdate(bytesDownloaded: reportedBytes, totalBytes: totalSize, speedBytesPerSecond: realtimeSpeed()))
                    }
                }
                if !buffer.isEmpty {
                    let flushed = Int64(buffer.count)
                    try fileHandle.write(contentsOf: buffer)
                    buffer.removeAll()
                    recordTransfer(flushed)
                }
                downloadedBytes = byteCount
                downloadComplete = true
            } catch let error as URLError where error.code.isTransientDownloadFailure && attempt < maxRetries {
                attempt += 1
                let delay = min(pow(2.0, Double(attempt - 1)), 30.0)
                try await Task.sleep(for: .seconds(delay))
            }
        }

        // Report 90% — now extract
        onProgress(DownloadUpdate(bytesDownloaded: Int64(Double(totalSize) * 0.9), totalBytes: totalSize, speedBytesPerSecond: 0))

        // Extract ZIP into a temp subdirectory, then flatten contents into destinationDir
        let extractTempDir = destinationDir.appendingPathComponent("_extract_temp")
        try? FileManager.default.removeItem(at: extractTempDir)
        try FileManager.default.createDirectory(at: extractTempDir, withIntermediateDirectories: true)

        try extractZip(at: tempZipURL, to: extractTempDir)

        // Flatten: if ZIP contained a single top-level folder, move its contents up
        let extractedItems = (try? FileManager.default.contentsOfDirectory(at: extractTempDir, includingPropertiesForKeys: nil)) ?? []
        var sourceDir = extractTempDir
        if extractedItems.count == 1, let single = extractedItems.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: single.path, isDirectory: &isDir), isDir.boolValue {
                sourceDir = single
            }
        }

        // Move extracted model files to destinationDir
        let modelFiles = (try? FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)) ?? []
        for item in modelFiles {
            let dest = destinationDir.appendingPathComponent(item.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: item, to: dest)
        }

        // Clean up
        try? FileManager.default.removeItem(at: extractTempDir)
        try? FileManager.default.removeItem(at: tempZipURL)

        // Write sentinel to mark successful extraction
        FileManager.default.createFile(atPath: sentinelURL.path, contents: Data())
        onProgress(DownloadUpdate(bytesDownloaded: totalSize, totalBytes: totalSize, speedBytesPerSecond: 0))
    }

    private func extractZip(at zipURL: URL, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let fm = FileManager.default
        // ZIPFoundation FileManager extension: skips __MACOSX entries automatically.
        try fm.unzipItem(at: zipURL, to: destinationURL)
    }
}

private extension Data {
    // No longer needed — extraction handled by ZIPFoundation FileManager extension.
}
