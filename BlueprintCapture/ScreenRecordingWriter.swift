import AVFoundation
import ReplayKit
import UIKit

final class ScreenRecordingWriter {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private let writingQueue = DispatchQueue(label: "com.blueprint.screenwriter", qos: .userInitiated)

    init(destinationURL: URL, outputSize: CGSize, orientation: UIInterfaceOrientation, includeAudio: Bool) throws {
        assetWriter = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        
        // Initialize audioInput first
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 192_000
            ]
            let audioInputInstance = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInputInstance.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(audioInputInstance) {
                assetWriter.add(audioInputInstance)
                self.audioInput = audioInputInstance
            } else {
                throw NSError(domain: "ScreenRecordingWriter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to add audio input to writer."])
            }
        } else {
            audioInput = nil
        }
        
        // Now we can use self to call transform
        videoInput.transform = transform(for: orientation)

        if assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
        } else {
            throw NSError(domain: "ScreenRecordingWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to add video input to writer."])
        }
    }

    func append(sampleBuffer: CMSampleBuffer, of type: RPSampleBufferType) {
        writingQueue.async { [weak self] in
            guard let self else { return }
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

            switch type {
            case .video:
                if !self.sessionStarted {
                    self.assetWriter.startWriting()
                    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    self.assetWriter.startSession(atSourceTime: time)
                    self.sessionStarted = true
                }
                guard self.assetWriter.status == .writing else { return }
                if self.videoInput.isReadyForMoreMediaData {
                    self.videoInput.append(sampleBuffer)
                }
            case .audioMic, .audioApp:
                guard let audioInput = self.audioInput, self.assetWriter.status == .writing else { return }
                if audioInput.isReadyForMoreMediaData {
                    audioInput.append(sampleBuffer)
                }
            @unknown default:
                break
            }
        }
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        writingQueue.async { [weak self] in
            guard let self else { return }
            if self.sessionStarted {
                self.videoInput.markAsFinished()
                self.audioInput?.markAsFinished()
            }
            self.assetWriter.finishWriting {
                if let error = self.assetWriter.error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}

private extension ScreenRecordingWriter {
    func transform(for orientation: UIInterfaceOrientation) -> CGAffineTransform {
        switch orientation {
        case .landscapeLeft:
            return CGAffineTransform(rotationAngle: .pi / 2)
        case .landscapeRight:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        case .portraitUpsideDown:
            return CGAffineTransform(rotationAngle: .pi)
        default:
            return .identity
        }
    }
}
