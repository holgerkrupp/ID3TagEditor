import AVFoundation
import Foundation

@Observable
@MainActor
final class WaveformPlaybackModel {
    var samples: [CGFloat] = []
    var duration: Double = 0
    var currentTime: Double = 0
    var isPlaying = false
    var isRenderingDetailedWaveform = false
    var errorMessage: String?

    private var url: URL?
    private var player: AVPlayer?
    private var timeObserver: Any?

    func load(url: URL) {
        guard self.url != url else {
            return
        }

        self.url = url
        samples = WaveformRenderer.placeholderSamples
        duration = 0
        currentTime = 0
        isPlaying = false
        isRenderingDetailedWaveform = true
        errorMessage = nil

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.08, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds.isFinite ? time.seconds : 0
            Task { @MainActor [weak self, seconds] in
                self?.currentTime = seconds
            }
        }

        Task {
            do {
                if let cached = await WaveformCache.shared.result(for: url) {
                    guard self.url == url else {
                        return
                    }
                    samples = cached.samples
                    duration = cached.duration
                    isRenderingDetailedWaveform = false
                    return
                }

                if let cachedPreview = await WaveformCache.shared.previewResult(for: url) {
                    guard self.url == url else {
                        return
                    }
                    samples = cachedPreview.samples
                    duration = cachedPreview.duration
                } else {
                    let preview = try await WaveformRenderer.renderPreview(url: url, bucketCount: 120)
                    await WaveformCache.shared.storePreview(preview, for: url)
                    guard self.url == url else {
                        return
                    }
                    samples = preview.samples
                    duration = preview.duration
                }

                let detailed = try await WaveformRenderer.render(url: url, bucketCount: 480)
                await WaveformCache.shared.store(detailed, for: url)
                guard self.url == url else {
                    return
                }
                samples = detailed.samples
                duration = detailed.duration
                isRenderingDetailedWaveform = false
            } catch {
                isRenderingDetailedWaveform = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        guard let player else {
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }
}

actor WaveformCache {
    static let shared = WaveformCache()

    private var results: [URL: WaveformRenderer.Result] = [:]
    private var previewResults: [URL: WaveformRenderer.Result] = [:]

    func result(for url: URL) -> WaveformRenderer.Result? {
        results[url]
    }

    func previewResult(for url: URL) -> WaveformRenderer.Result? {
        previewResults[url]
    }

    func store(_ result: WaveformRenderer.Result, for url: URL) {
        results[url] = result
    }

    func storePreview(_ result: WaveformRenderer.Result, for url: URL) {
        previewResults[url] = result
    }
}

enum WaveformRenderer {
    struct Result: Sendable {
        var samples: [CGFloat]
        var duration: Double
    }

    nonisolated static let placeholderSamples = Array(repeating: CGFloat(0.03), count: 160)

    nonisolated static func renderPreview(url: URL, bucketCount: Int) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else {
                return Result(samples: placeholderSamples, duration: 0)
            }

            let durationTime = try await asset.load(.duration)
            let duration = durationTime.seconds.isFinite ? durationTime.seconds : 0
            let bucketCount = max(48, bucketCount)
            guard duration > 0 else {
                return Result(samples: placeholderSamples, duration: 0)
            }

            var sampleRate = 44_100.0
            var channelCount = 2
            if let formatDescription = try await track.load(.formatDescriptions).first,
               let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                sampleRate = streamDescription.pointee.mSampleRate
                channelCount = max(Int(streamDescription.pointee.mChannelsPerFrame), 1)
            }

            let windowSeconds = min(max(duration / Double(bucketCount) * 0.18, 0.04), 0.18)
            var peaks = Array(repeating: Float(0), count: bucketCount)

            for bucket in 0..<bucketCount {
                try Task.checkCancellation()
                let center = duration * (Double(bucket) + 0.5) / Double(bucketCount)
                let start = max(0, center - windowSeconds / 2)
                peaks[bucket] = try readPeak(
                    asset: asset,
                    track: track,
                    start: start,
                    duration: min(windowSeconds, duration - start),
                    sampleRate: sampleRate,
                    channelCount: channelCount
                )
            }

            let samples = peaks.map { peak in
                scaledAmplitude(for: peak)
            }
            return Result(samples: samples, duration: duration)
        }.value
    }

    nonisolated static func render(url: URL, bucketCount: Int) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else {
                return Result(samples: placeholderSamples, duration: 0)
            }

            let durationTime = try await asset.load(.duration)
            let duration = durationTime.seconds.isFinite ? durationTime.seconds : 0
            let bucketCount = max(64, bucketCount)
            guard duration > 0 else {
                return Result(samples: placeholderSamples, duration: 0)
            }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMBitDepthKey: 16
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                return Result(samples: placeholderSamples, duration: duration)
            }
            reader.add(output)

            var sampleRate = 44_100.0
            var channelCount = 2
            if let formatDescription = try await track.load(.formatDescriptions).first,
               let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                sampleRate = streamDescription.pointee.mSampleRate
                channelCount = max(Int(streamDescription.pointee.mChannelsPerFrame), 1)
            }

            let totalFrames = max(Int(duration * sampleRate), 1)
            var bucketSquareSums = Array(repeating: Double(0), count: bucketCount)
            var bucketFrameCounts = Array(repeating: 0, count: bucketCount)
            var processedFrames = 0
            reader.startReading()

            while let sampleBuffer = output.copyNextSampleBuffer(), CMSampleBufferIsValid(sampleBuffer) {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    continue
                }

                let byteLength = CMBlockBufferGetDataLength(blockBuffer)
                guard byteLength > 0 else {
                    continue
                }

                var data = Data(count: byteLength)
                let copyResult = data.withUnsafeMutableBytes { bytes in
                    CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: byteLength,
                        destination: bytes.baseAddress!
                    )
                }
                guard copyResult == kCMBlockBufferNoErr else {
                    continue
                }

                data.withUnsafeBytes { rawBuffer in
                    let pcm = rawBuffer.bindMemory(to: Int16.self)
                    guard !pcm.isEmpty else {
                        return
                    }

                    let frameCount = max(pcm.count / channelCount, 1)
                    for frameIndex in 0..<frameCount {
                        var frameSquareSum = Double(0)
                        var frameChannelCount = 0
                        for channel in 0..<channelCount {
                            let sampleIndex = frameIndex * channelCount + channel
                            guard sampleIndex < pcm.count else {
                                continue
                            }
                            let normalizedSample = Double(pcm[sampleIndex]) / Double(Int16.max)
                            frameSquareSum += normalizedSample * normalizedSample
                            frameChannelCount += 1
                        }

                        let bucket = min(bucketCount - 1, (processedFrames + frameIndex) * bucketCount / totalFrames)
                        if frameChannelCount > 0 {
                            bucketSquareSums[bucket] += frameSquareSum / Double(frameChannelCount)
                            bucketFrameCounts[bucket] += 1
                        }
                    }

                    processedFrames += frameCount
                }
            }

            if reader.status == .failed {
                throw reader.error ?? CocoaError(.fileReadUnknown)
            }

            let loudnessLevels = zip(bucketSquareSums, bucketFrameCounts).map { squareSum, frameCount in
                guard frameCount > 0 else {
                    return 0.0
                }
                return sqrt(squareSum / Double(frameCount))
            }
            let samples = scaledAmplitudes(for: loudnessLevels)
            return Result(samples: samples, duration: duration)
        }.value
    }

    nonisolated private static func scaledAmplitude(for peak: Float) -> CGFloat {
        let clampedPeak = min(max(Double(peak), 0), 1)
        let logarithmic = log10(1 + 9 * clampedPeak)
        return CGFloat(min(max(logarithmic * 0.82 + 0.03, 0.03), 0.88))
    }

    nonisolated private static func scaledAmplitudes(for levels: [Double]) -> [CGFloat] {
        guard !levels.isEmpty else {
            return []
        }

        let sortedLevels = levels.filter { $0.isFinite && $0 > 0 }.sorted()
        guard let referenceLevel = percentile(0.95, in: sortedLevels), referenceLevel > 0 else {
            return Array(repeating: CGFloat(0.03), count: levels.count)
        }

        return levels.map { level in
            let normalized = min(max(level / referenceLevel, 0), 1)
            let decibels = 20 * log10(max(normalized, 0.000_1))
            let loudness = min(max((decibels + 45) / 45, 0), 1)
            return CGFloat(min(max(pow(loudness, 1.35) * 0.82 + 0.03, 0.03), 0.88))
        }
    }

    nonisolated private static func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else {
            return nil
        }

        let clampedPercentile = min(max(percentile, 0), 1)
        let index = Int((Double(sortedValues.count - 1) * clampedPercentile).rounded())
        return sortedValues[index]
    }

    nonisolated private static func readPeak(
        asset: AVAsset,
        track: AVAssetTrack,
        start: Double,
        duration: Double,
        sampleRate: Double,
        channelCount: Int
    ) throws -> Float {
        guard duration > 0 else {
            return 0.03
        }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMBitDepthKey: 16
        ])
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            return 0.03
        }
        reader.add(output)
        reader.startReading()

        var peak: Float = 0
        let maxFrames = max(Int(sampleRate * duration), 1)
        var processedFrames = 0

        while processedFrames < maxFrames,
              let sampleBuffer = output.copyNextSampleBuffer(),
              CMSampleBufferIsValid(sampleBuffer) {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            let byteLength = CMBlockBufferGetDataLength(blockBuffer)
            guard byteLength > 0 else {
                continue
            }

            var data = Data(count: byteLength)
            let copyResult = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: byteLength,
                    destination: bytes.baseAddress!
                )
            }
            guard copyResult == kCMBlockBufferNoErr else {
                continue
            }

            data.withUnsafeBytes { rawBuffer in
                let pcm = rawBuffer.bindMemory(to: Int16.self)
                guard !pcm.isEmpty else {
                    return
                }

                let frameCount = max(pcm.count / channelCount, 1)
                for frameIndex in 0..<frameCount {
                    var framePeak: Float = 0
                    for channel in 0..<channelCount {
                        let sampleIndex = frameIndex * channelCount + channel
                        guard sampleIndex < pcm.count else {
                            continue
                        }
                        framePeak = max(framePeak, abs(Float(pcm[sampleIndex])) / Float(Int16.max))
                    }
                    peak = max(peak, framePeak)
                }
                processedFrames += frameCount
            }
        }

        if reader.status == .failed {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        return max(peak, 0.03)
    }
}
