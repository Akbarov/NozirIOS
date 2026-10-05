import Foundation

/// The year as a child's birth year is counted: always Gregorian, in the
/// phone's time zone, whatever calendar the phone is set to (a Buddhist or
/// Japanese calendar would otherwise give the wrong age).
@usableFromInline
enum Gregorian {
    @usableFromInline
    static var currentYear: Int {
        Calendar(identifier: .gregorian).component(.year, from: Date())
    }
}
