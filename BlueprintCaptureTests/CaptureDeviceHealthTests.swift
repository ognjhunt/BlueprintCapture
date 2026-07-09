import Foundation
import Testing
@testable import BlueprintCapture

/// Unit tests for the pure device-health evaluation seam used during recording
/// (thermal / memory / disk monitoring, finding R008). These exercise only the
/// `nonisolated static` decision logic, so they need no simulator, AVFoundation,
/// or ARKit runtime — CI compiles and runs them in the hermetic lane.
@MainActor
struct CaptureDeviceHealthTests {

    private let plentyOfDisk: Int64 = 5_000_000_000        // 5 GB
    private let lowDisk: Int64 = 700_000_000               // 700 MB (< 1 GB warn, >= 300 MB stop)
    private let criticalDisk: Int64 = 100_000_000          // 100 MB (< 300 MB stop)

    @Test
    func healthyDeviceProducesNoWarning() {
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .nominal,
            memoryWarningActive: false,
            availableDiskBytes: plentyOfDisk
        )
        #expect(result == nil)
    }

    @Test
    func fairThermalIsStillHealthy() {
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .fair,
            memoryWarningActive: false,
            availableDiskBytes: plentyOfDisk
        )
        #expect(result == nil)
    }

    @Test
    func seriousThermalIsSoftWarning() {
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .serious,
            memoryWarningActive: false,
            availableDiskBytes: plentyOfDisk
        )
        #expect(result == .elevatedThermal)
        #expect(result?.isHardLimit == false)
    }

    @Test
    func criticalThermalIsHardLimit() {
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .critical,
            memoryWarningActive: false,
            availableDiskBytes: plentyOfDisk
        )
        #expect(result == .criticalThermal)
        #expect(result?.isHardLimit == true)
    }

    @Test
    func memoryWarningIsHardLimit() {
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .nominal,
            memoryWarningActive: true,
            availableDiskBytes: plentyOfDisk
        )
        #expect(result == .memoryPressure)
        #expect(result?.isHardLimit == true)
    }

    @Test
    func lowDiskIsSoftWarning() {
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .nominal,
            memoryWarningActive: false,
            availableDiskBytes: lowDisk
        )
        #expect(result == .lowDisk)
        #expect(result?.isHardLimit == false)
    }

    @Test
    func criticalDiskIsHardLimit() {
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .nominal,
            memoryWarningActive: false,
            availableDiskBytes: criticalDisk
        )
        #expect(result == .criticalDisk)
        #expect(result?.isHardLimit == true)
    }

    @Test
    func criticalDiskTakesPriorityOverThermal() {
        // Even with only a serious (soft) thermal state, a critically low disk must win
        // and force a hard-limit stop so the capture-so-far is preserved.
        let result = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .serious,
            memoryWarningActive: true,
            availableDiskBytes: criticalDisk
        )
        #expect(result == .criticalDisk)
        #expect(result?.isHardLimit == true)
    }

    @Test
    func unknownDiskFallsBackToThermalAndMemory() {
        // A nil disk reading (API unavailable) must not crash or fabricate a disk warning;
        // thermal / memory signals still drive the result.
        let healthy = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .nominal,
            memoryWarningActive: false,
            availableDiskBytes: nil
        )
        #expect(healthy == nil)

        let hot = CaptureQualityMonitor.evaluateDeviceHealth(
            thermalState: .critical,
            memoryWarningActive: false,
            availableDiskBytes: nil
        )
        #expect(hot == .criticalThermal)
    }
}
