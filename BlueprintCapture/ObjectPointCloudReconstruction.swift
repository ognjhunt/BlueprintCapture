#if canImport(ARKit)
import Foundation
import ARKit
import Accelerate

@available(iOS 16.0, *)
final class ObjectPointCloudReconstruction {
    struct SegmentationMask {
        let identifier: UUID
        let label: String?
        let pixelBuffer: CVPixelBuffer
        let confidence: Float
    }

    struct SegmentationFrame {
        let timestamp: TimeInterval
        let masks: [SegmentationMask]
    }

    struct ObjectSummary: Codable, Equatable {
        struct BoundingBox: Codable, Equatable {
            let center: [Double]
            let extents: [Double]
            let axes: [[Double]]
            let orientationQuaternion: [Double]
        }

        let id: UUID
        let label: String?
        let pointCount: Int
        let centroid: [Double]
        let averageConfidence: Double?
        let boundingBox: BoundingBox
        let pointCloudFile: String
    }

    struct Output {
        let indexURL: URL
        let objectCount: Int
        let summaries: [ObjectSummary]
    }

    private struct ObjectAccumulator {
        var id: UUID
        var label: String?
        var reservoir: ContiguousArray<SIMD3<Float>> = []
        var confidences: ContiguousArray<UInt8> = []
        var totalSamples: Int = 0
        var maxSamples: Int

        mutating func append(point: SIMD3<Float>, confidence: UInt8) {
            totalSamples += 1
            if reservoir.count < maxSamples {
                reservoir.append(point)
                confidences.append(confidence)
                return
            }

            let replaceIndex = Int.random(in: 0..<totalSamples)
            guard replaceIndex < maxSamples else { return }
            reservoir[replaceIndex] = point
            confidences[replaceIndex] = confidence
        }
    }

    private let outputDirectory: URL
    private let indexURL: URL
    private var segmentationFrames: [SegmentationFrame] = []
    private var accumulators: [UUID: ObjectAccumulator] = [:]
    private let timestampTolerance: TimeInterval
    private let maskThreshold: UInt8
    private let maxSamplesPerObject: Int

    init(outputDirectory: URL, indexURL: URL, timestampTolerance: TimeInterval = 1.0 / 15.0, maskThreshold: UInt8 = 1, maxSamplesPerObject: Int = 200_000) {
        self.outputDirectory = outputDirectory
        self.indexURL = indexURL
        self.timestampTolerance = timestampTolerance
        self.maskThreshold = maskThreshold
        self.maxSamplesPerObject = maxSamplesPerObject
    }

    func reset() {
        segmentationFrames.removeAll()
        accumulators.removeAll()
    }

    func enqueue(segmentationFrame frame: SegmentationFrame) {
        guard !frame.masks.isEmpty else { return }
        segmentationFrames.append(frame)
        segmentationFrames.sort { $0.timestamp < $1.timestamp }
    }

    func process(frame: ARFrame) {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let timestamp = frame.timestamp
        guard !segmentationFrames.isEmpty else { return }

        var indicesToRemove: [Int] = []
        for (index, segmentation) in segmentationFrames.enumerated() {
            if abs(segmentation.timestamp - timestamp) <= timestampTolerance {
                process(segmentation: segmentation, with: frame, depthData: depthData)
                indicesToRemove.append(index)
            } else if segmentation.timestamp < timestamp - timestampTolerance {
                // Drop stale segmentation frames we never matched.
                indicesToRemove.append(index)
            } else if segmentation.timestamp > timestamp + timestampTolerance {
                break
            }
        }

        for index in indicesToRemove.sorted(by: >) {
            segmentationFrames.remove(at: index)
        }
    }

    func finalize() -> Output? {
        guard !accumulators.isEmpty else { return nil }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create object reconstruction directory: \(error)")
            return nil
        }

        var summaries: [ObjectSummary] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        for accumulator in accumulators.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard !accumulator.reservoir.isEmpty else { continue }
            let summary = buildSummary(for: accumulator)
            let fileURL = outputDirectory.appendingPathComponent("\(accumulator.id.uuidString).ply")
            do {
                try writePointCloud(for: accumulator, to: fileURL)
            } catch {
                print("Failed to write point cloud for object \(accumulator.id): \(error)")
                continue
            }
            summaries.append(summary)
        }

        guard !summaries.isEmpty else { return nil }

        do {
            let data = try encoder.encode(summaries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("Failed to persist object reconstruction index: \(error)")
            return nil
        }

        return Output(indexURL: indexURL, objectCount: summaries.count, summaries: summaries)
    }

    private func process(segmentation: SegmentationFrame, with frame: ARFrame, depthData: ARDepthData) {
        let depthMap = depthData.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let depthFloatsPerRow = depthBytesPerRow / MemoryLayout<Float32>.size
        let depthPointer = depthBase.assumingMemoryBound(to: Float32.self)

        var confidencePointer: UnsafePointer<UInt8>?
        var confidenceStride: Int = 0
        if let confidenceMap = depthData.confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
            confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap) / MemoryLayout<UInt8>.size
            if let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap) {
                confidencePointer = UnsafePointer(confidenceBase.assumingMemoryBound(to: UInt8.self))
            }
        }

        let intrinsics = frame.camera.intrinsics
        let referenceDimensions = CGSize(width: CGFloat(depthWidth), height: CGFloat(depthHeight))
        let scaleX = Float(referenceDimensions.width) / Float(depthWidth)
        let scaleY = Float(referenceDimensions.height) / Float(depthHeight)
        let inverseIntrinsics = simd_inverse(intrinsics)
        let cameraTransform = frame.camera.transform

        for mask in segmentation.masks {
            guard let maskValues = makeMaskValues(from: mask.pixelBuffer, targetWidth: depthWidth, targetHeight: depthHeight) else { continue }
            var accumulator = accumulators[mask.identifier] ?? ObjectAccumulator(id: mask.identifier, label: mask.label, maxSamples: maxSamplesPerObject)
            if accumulator.label == nil { accumulator.label = mask.label }

            maskValues.withUnsafeBufferPointer { maskBuffer in
                for y in 0..<depthHeight {
                    let depthRow = depthPointer.advanced(by: y * depthFloatsPerRow)
                    let maskRow = maskBuffer.baseAddress!.advanced(by: y * depthWidth)
                    let confidenceRow = confidencePointer.map { $0.advanced(by: y * confidenceStride) }
                    for x in 0..<depthWidth {
                        if maskRow[x] < maskThreshold { continue }
                        let depthValue = depthRow[x]
                        guard depthValue.isFinite, depthValue > 0 else { continue }

                        let px = (Float(x) + 0.5) * scaleX
                        let py = (Float(y) + 0.5) * scaleY
                        let homogeneous = SIMD3<Float>(px, py, 1.0)
                        let direction = inverseIntrinsics * homogeneous
                        let cameraPoint = direction * depthValue
                        let worldPointHomogeneous = cameraTransform * SIMD4<Float>(cameraPoint, 1.0)
                        let worldPoint = SIMD3<Float>(worldPointHomogeneous.x, worldPointHomogeneous.y, worldPointHomogeneous.z)

                        let depthConfidence: Float
                        if let confidenceRow {
                            let rawValue = confidenceRow[x]
                            depthConfidence = Float(rawValue) / 2.0
                        } else {
                            depthConfidence = 1.0
                        }
                        let combinedConfidence = max(0.0, min(1.0, depthConfidence * max(0.0, min(1.0, mask.confidence))))
                        let confidenceEncoded = UInt8(max(0, min(255, Int(round(combinedConfidence * 255.0)))))
                        accumulator.append(point: worldPoint, confidence: confidenceEncoded)
                    }
                }
            }

            accumulators[mask.identifier] = accumulator
        }
    }

    private func makeMaskValues(from buffer: CVPixelBuffer, targetWidth: Int, targetHeight: Int) -> [UInt8]? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_OneComponent8 else {
            print("Unsupported mask pixel format: \(format)")
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let sourcePointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        if width == targetWidth && height == targetHeight {
            var values = [UInt8](repeating: 0, count: targetWidth * targetHeight)
            values.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                for row in 0..<height {
                    let src = sourcePointer.advanced(by: row * bytesPerRow)
                    let dst = base.advanced(by: row * targetWidth)
                    dst.assign(from: src, count: targetWidth)
                }
            }
            return values
        }

        var source = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: baseAddress),
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )

        let targetRowBytes = targetWidth
        guard let destinationData = malloc(targetHeight * targetRowBytes) else { return nil }
        var destination = vImage_Buffer(
            data: destinationData,
            height: vImagePixelCount(targetHeight),
            width: vImagePixelCount(targetWidth),
            rowBytes: targetRowBytes
        )
        defer { free(destination.data) }

        let error = vImageScale_Planar8(&source, &destination, nil, vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else {
            print("Failed to scale mask buffer: \(error)")
            return nil
        }

        let pointer = destination.data.assumingMemoryBound(to: UInt8.self)
        return [UInt8](UnsafeBufferPointer(start: pointer, count: targetWidth * targetHeight))
    }

    private func buildSummary(for accumulator: ObjectAccumulator) -> ObjectSummary {
        let points = accumulator.reservoir
        let centroid = computeCentroid(points: points)
        let (axes, extents, obbCenter) = computePrincipalAxes(points: points, centroid: centroid)
        let rotationMatrix = simd_float3x3(columns: (axes[0], axes[1], axes[2]))
        let quaternion = simd_quatf(rotationMatrix)

        let averageConfidence: Double?
        if accumulator.confidences.isEmpty {
            averageConfidence = nil
        } else {
            let sum = accumulator.confidences.reduce(0) { $0 + Int($1) }
            averageConfidence = Double(sum) / Double(accumulator.confidences.count * 255)
        }

        let boundingBox = ObjectSummary.BoundingBox(
            center: [Double(obbCenter.x), Double(obbCenter.y), Double(obbCenter.z)],
            extents: [Double(extents.x), Double(extents.y), Double(extents.z)],
            axes: axes.map { [Double($0.x), Double($0.y), Double($0.z)] },
            orientationQuaternion: [Double(quaternion.vector.x), Double(quaternion.vector.y), Double(quaternion.vector.z), Double(quaternion.vector.w)]
        )

        return ObjectSummary(
            id: accumulator.id,
            label: accumulator.label,
            pointCount: points.count,
            centroid: [Double(centroid.x), Double(centroid.y), Double(centroid.z)],
            averageConfidence: averageConfidence,
            boundingBox: boundingBox,
            pointCloudFile: "\(accumulator.id.uuidString).ply"
        )
    }

    private func computeCentroid(points: ContiguousArray<SIMD3<Float>>) -> SIMD3<Float> {
        guard !points.isEmpty else { return SIMD3<Float>(repeating: 0) }
        var sum = SIMD3<Float>(repeating: 0)
        for point in points { sum += point }
        return sum / Float(points.count)
    }

    private func computePrincipalAxes(points: ContiguousArray<SIMD3<Float>>, centroid: SIMD3<Float>) -> ([SIMD3<Float>], SIMD3<Float>, SIMD3<Float>) {
        guard points.count >= 3 else {
            let axes = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)]
            return (axes, SIMD3<Float>(repeating: 0), centroid)
        }

        var covariance = simd_double3x3(0)
        for point in points {
            let diff = SIMD3<Double>(Double(point.x - centroid.x), Double(point.y - centroid.y), Double(point.z - centroid.z))
            let column0 = SIMD3<Double>(diff.x * diff.x, diff.y * diff.x, diff.z * diff.x)
            let column1 = SIMD3<Double>(diff.x * diff.y, diff.y * diff.y, diff.z * diff.y)
            let column2 = SIMD3<Double>(diff.x * diff.z, diff.y * diff.z, diff.z * diff.z)
            covariance += simd_double3x3(columns: (column0, column1, column2))
        }
        covariance /= Double(points.count)

        let decomposition = eigenvectors(for: covariance)
        let eigenVectors: [SIMD3<Float>]
        if let decomposition {
            eigenVectors = decomposition.vectors.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
        } else {
            eigenVectors = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)]
        }

        var basis = simd_float3x3(columns: (normalize(eigenVectors[0]), normalize(eigenVectors[1]), normalize(eigenVectors[2])))
        if simd_determinant(basis) < 0 {
            basis.columns.2 = -basis.columns.2
        }

        var minValues = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxValues = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for point in points {
            let offset = point - centroid
            let projections = SIMD3<Float>(simd_dot(offset, basis.columns.0), simd_dot(offset, basis.columns.1), simd_dot(offset, basis.columns.2))
            minValues = min(minValues, projections)
            maxValues = max(maxValues, projections)
        }

        let extents = maxValues - minValues
        let centerOffset = (minValues + maxValues) * 0.5
        let obbCenter = centroid + basis.columns.0 * centerOffset.x + basis.columns.1 * centerOffset.y + basis.columns.2 * centerOffset.z

        return ([basis.columns.0, basis.columns.1, basis.columns.2], extents, obbCenter)
    }

    private func eigenvectors(for matrix: simd_double3x3) -> (values: [Double], vectors: [SIMD3<Double>])? {
        var jobz: Int8 = 86 // 'V'
        var uplo: Int8 = 76 // 'L'
        var n: Int32 = 3
        var a: [Double] = [
            matrix[0, 0], matrix[1, 0], matrix[2, 0],
            matrix[0, 1], matrix[1, 1], matrix[2, 1],
            matrix[0, 2], matrix[1, 2], matrix[2, 2]
        ]
        var lda: Int32 = 3
        var w = [Double](repeating: 0, count: Int(n))
        var lwork: Int32 = max(1, 3 * n)
        var work = [Double](repeating: 0, count: Int(lwork))
        var info: Int32 = 0
        dsyev_(&jobz, &uplo, &n, &a, &lda, &w, &work, &lwork, &info)
        guard info == 0 else { return nil }

        let vectors = [
            SIMD3<Double>(a[0], a[1], a[2]),
            SIMD3<Double>(a[3], a[4], a[5]),
            SIMD3<Double>(a[6], a[7], a[8])
        ]

        // Sort eigenvalues descending by magnitude to align principal axes.
        let combined = zip(w, vectors).sorted { $0.0 > $1.0 }
        let sortedValues = combined.map { $0.0 }
        let sortedVectors = combined.map { $0.1 }
        return (sortedValues, sortedVectors)
    }

    private func writePointCloud(for accumulator: ObjectAccumulator, to url: URL) throws {
        var lines: [String] = []
        lines.reserveCapacity(accumulator.reservoir.count + 10)
        lines.append("ply")
        lines.append("format ascii 1.0")
        lines.append("element vertex \(accumulator.reservoir.count)")
        lines.append("property float x")
        lines.append("property float y")
        lines.append("property float z")
        lines.append("property uchar confidence")
        lines.append("end_header")
        for (index, point) in accumulator.reservoir.enumerated() {
            let confidence = index < accumulator.confidences.count ? accumulator.confidences[index] : 255
            lines.append(String(format: "%.6f %.6f %.6f %d", point.x, point.y, point.z, confidence))
        }
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
