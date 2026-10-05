import Foundation
import Testing
@testable import NozirDesignSystem

@Suite struct ChildSwitcherTests {
    private let ali = UUID()
    private let vali = UUID()

    @Test func tappingAChildSelectsIt() {
        #expect(NozirChildSwitcher.selection(afterTapping: ali, current: nil, allowsAll: true) == ali)
        #expect(NozirChildSwitcher.selection(afterTapping: vali, current: ali, allowsAll: true) == vali)
    }

    @Test func tappingTheChosenChildAgainGoesBackToEveryoneWhereThereIsAnEveryone() {
        #expect(NozirChildSwitcher.selection(afterTapping: ali, current: ali, allowsAll: true) == nil)
        #expect(NozirChildSwitcher.selection(afterTapping: ali, current: ali, allowsAll: false) == ali)
    }

    @Test func tappingEveryoneClearsTheChoice() {
        #expect(NozirChildSwitcher.selection(afterTapping: nil, current: ali, allowsAll: true) == nil)
    }

    @Test func aChipIsReadAsItsNameUnlessToldOtherwise() {
        #expect(NozirSwitcherChild(id: ali, name: "Ali", tone: .forKey(nil, position: 0)).accessibilityLabel == "Ali")
        #expect(NozirSwitcherChild(id: ali, name: "Ali", tone: .forKey(nil, position: 0), accessibilityLabel: "Ali avatari").accessibilityLabel == "Ali avatari")
    }
}
