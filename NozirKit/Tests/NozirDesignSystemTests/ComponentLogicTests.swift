import Testing
import UIKit
@testable import NozirDesignSystem

@Suite struct UzbekPhoneTests {
    @Test func typedDigitsAreKeptUpToNine() {
        #expect(UzbekPhone.digits(from: "90 123") == "90123")
        #expect(UzbekPhone.digits(from: "9012345678") == "901234567")
        #expect(UzbekPhone.digits(from: "90a1") == "901")
    }

    // Review Focus 4.
    @Test(arguments: ["+998 90 123-45-67", "998901234567", "+998901234567"])
    func aPastedFullNumberKeepsTheSubscriberDigits(pasted: String) {
        #expect(UzbekPhone.digits(from: pasted) == "901234567")
    }

    @Test func digitsAreGroupedAsTheyArePrinted() {
        #expect(UzbekPhone.grouped("901234567") == "90 123 45 67")
        #expect(UzbekPhone.grouped("9012") == "90 12")
        #expect(UzbekPhone.grouped("") == "")
    }

    @Test func onlyAFullNumberHasAnE164Form() {
        #expect(UzbekPhone.e164("901234567") == "+998901234567")
        #expect(UzbekPhone.e164("90123") == nil)
    }

    @Test func aStoredNumberReadsBack() {
        #expect(UzbekPhone.digits(fromE164: "+998901234567") == "901234567")
        #expect(UzbekPhone.digits(fromE164: nil) == "")
        #expect(UzbekPhone.display("+998901234567") == "+998 90 123 45 67")
    }
}

@Suite struct AvatarTests {
    @Test func aKnownKeyIsItsTone() {
        #expect(AvatarTone.forKey("sky") == .sky)
    }

    @Test func anUnknownKeyFallsBackByPosition() {
        #expect(AvatarTone.forKey(nil) == .teal)
        #expect(AvatarTone.forKey("violet", position: 1) == .apricot)
        #expect(AvatarTone.forKey("violet", position: 5) == .sky)
    }

    @Test func theInitialIsTheNamesFirstLetter() {
        #expect(NozirAvatar.initial(of: "  ali", fallback: "A") == "A")
        #expect(NozirAvatar.initial(of: "vali", fallback: "A") == "V")
        #expect(NozirAvatar.initial(of: " ", fallback: "A") == "A")
    }
}

@Suite struct QRCodeTests {
    @Test func aPayloadBecomesASquareImage() throws {
        let image = try #require(NozirQRCode.image(for: "nozir://pair?code=472918"))
        #expect(image.size.width == image.size.height)
        #expect(image.size.width > 0)
    }
}
