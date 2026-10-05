import Testing
@testable import NozirDesignSystem

@Suite struct ChartMathTests {
    @Test func heightsAreAShareOfThePeakFromZero() {
        #expect(ChartMath.fractions([30, 60, 0, 15]) == [0.5, 1, 0, 0.25])
    }

    @Test func aWeekOfZerosHasNoHeightAndNoPeak() {
        #expect(ChartMath.fractions([0, 0, 0]) == [0, 0, 0])
        #expect(ChartMath.peakIndex([0, 0, 0]) == nil)
        #expect(ChartMath.fractions([]) == [])
        #expect(ChartMath.peakIndex([]) == nil)
    }

    @Test func theFirstOfEqualPeaksIsMarked() {
        #expect(ChartMath.peakIndex([10, 40, 5, 40]) == 1)
    }

    @Test func aNegativeValueDrawsNothing() {
        #expect(ChartMath.fractions([-5, 10]) == [0, 1])
    }

    @Test func sharesAddUpToTheWhole() {
        let shares = ChartMath.shares([50, 25, 25])
        #expect(shares == [0.5, 0.25, 0.25])
        #expect(ChartMath.shares([0, 0]) == [0, 0])
    }
}
