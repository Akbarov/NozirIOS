import Testing
import NozirDesignSystem
@testable import NozirAppFeature

@MainActor
@Suite struct AddChildModelTests {
    private func makeModel() -> AddChildModel {
        AddChildModel(currentYear: 2026)
    }

    @Test(arguments: zip(["2019", "2015", "2009", "2020", "2008", "201", "1990"], [7, 11, 17, nil, nil, nil, nil] as [Int?]))
    func onlyAnAgeTheChildAppHasABandForCounts(year: String, age: Int?) {
        let model = makeModel()
        model.updateBirthYear(year)

        #expect(model.age == age)
    }

    @Test func theYearKeepsFourDigitsOnly() {
        let model = makeModel()

        model.updateBirthYear("20a155")

        #expect(model.birthYearText == "2015")
    }

    @Test func aNameIsCappedAtFortyAndTrimmedInTheDraft() {
        let model = makeModel()
        model.updateName(String(repeating: "a", count: 45))
        #expect(model.name.count == 40)

        model.updateName("  Ali ")
        model.updateBirthYear("2015")

        #expect(model.draft?.displayName == "Ali")
    }

    @Test func aBlankNameCannotContinue() {
        let model = makeModel()
        model.updateName("   ")
        model.updateBirthYear("2015")

        #expect(!model.canContinue)
    }

    @Test func aPartialPhoneIsAnErrorAndAnEmptyOneIsNot() {
        let model = makeModel()
        model.updateName("Ali")
        model.updateBirthYear("2015")

        model.updatePhone("90123")
        #expect(model.showsPhoneError)
        #expect(!model.canContinue)

        model.updatePhone("")
        #expect(!model.showsPhoneError)
        #expect(model.canContinue)
    }

    @Test func theDraftCarriesWhatTheParentGave() {
        let model = makeModel()
        model.updateName("Ali")
        model.updateBirthYear("2015")
        model.updatePhone("+998 90 123 45 67")
        model.avatar = .sky

        #expect(model.draft == ChildDraft(displayName: "Ali", birthYear: 2015, avatarKey: "sky", phoneE164: "+998901234567"))
    }
}
