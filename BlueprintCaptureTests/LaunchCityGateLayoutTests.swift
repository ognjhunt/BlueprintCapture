import CoreGraphics
import Testing
@testable import BlueprintCapture

struct LaunchCityGateLayoutTests {

    @Test
    func compactWidthsUseSmallerTypeAndVerticalStatusLayout() {
        let metrics = LaunchCityGateLayoutMetrics(containerWidth: 393)

        #expect(metrics.isCompactWidth)
        #expect(metrics.heroTitleSize == 32)
        #expect(metrics.statusTitleSize == 20)
        #expect(metrics.usesVerticalStatusLayout)
        #expect(metrics.headerTopPadding == 52)
    }

    @Test
    func regularWidthsKeepLargerTypeAndHorizontalStatusLayout() {
        let metrics = LaunchCityGateLayoutMetrics(containerWidth: 430)

        #expect(metrics.isCompactWidth == false)
        #expect(metrics.heroTitleSize == 38)
        #expect(metrics.statusTitleSize == 24)
        #expect(metrics.usesVerticalStatusLayout == false)
        #expect(metrics.headerTopPadding == 68)
    }
}
