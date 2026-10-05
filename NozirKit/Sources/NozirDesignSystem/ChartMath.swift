/// Android `ChartFractions.kt`: the arithmetic behind every chart, kept apart
/// from drawing so it can be tested.
public enum ChartMath {
    /// Each value over the largest, from a zero baseline, clamped to 0...1. A
    /// list of zeros (or an empty one) draws nothing rather than dividing by zero.
    public static func fractions(_ values: [Int]) -> [Double] {
        guard let peak = values.max(), peak > 0 else { return values.map { _ in 0 } }
        return values.map { min(max(Double($0) / Double(peak), 0), 1) }
    }

    /// The first index holding the largest value; nil when nothing is above zero.
    public static func peakIndex(_ values: [Int]) -> Int? {
        guard let peak = values.max(), peak > 0 else { return nil }
        return values.firstIndex(of: peak)
    }

    /// Each value's part of the sum (negatives count as zero).
    public static func shares(_ values: [Int]) -> [Double] {
        let total = values.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return values.map { _ in 0 } }
        return values.map { Double(max($0, 0)) / Double(total) }
    }
}
