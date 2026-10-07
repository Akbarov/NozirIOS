import Foundation
import NozirInsights

/// Android `partialMinutesOf`: the smaller amount a parent can offer instead
/// of the whole ask, or nil when there is none worth a button.
///
/// Minutes: roughly half, rounded down to a figure a person would say ("15",
/// not "17"); nothing below five, and never the whole ask again. A bedtime
/// moves in the steps the child chose from (15 or 30): half an hour halves to
/// a quarter, a quarter has no half.
enum PartialMinutes {
    static func of(_ request: ExtraTimeRequest) -> Int? {
        switch request.kind {
        case .bedtimeDelay:
            return request.requestedMinutes > 15 ? 15 : nil
        case .extraMinutes:
            let rounded = request.requestedMinutes / 2 / 5 * 5
            guard rounded >= 5, rounded < request.requestedMinutes else { return nil }
            return rounded
        case .unknown:
            return nil
        }
    }
}
