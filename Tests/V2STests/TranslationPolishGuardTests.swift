import XCTest
@testable import v2s

final class TranslationPolishGuardTests: XCTestCase {
    private let original = "Saya akan sangat berterima kasih jika Anda dapat menyiapkan materi sebelum Senin depan."

    func testAcceptsASimilarRewrite() {
        XCTAssertTrue(TranslationPolishGuard.accepts(
            original: original,
            candidate: "Saya sangat berterima kasih kalau Anda bisa menyiapkan materi sebelum Senin depan."
        ))
    }

    func testRejectsEmptyOrUnchangedOutput() {
        XCTAssertFalse(TranslationPolishGuard.accepts(original: original, candidate: "  "))
        XCTAssertFalse(TranslationPolishGuard.accepts(original: original, candidate: original))
    }

    func testRejectsDroppedOrBloatedOutput() {
        XCTAssertFalse(TranslationPolishGuard.accepts(original: original, candidate: "Siapkan materinya."))
        XCTAssertFalse(TranslationPolishGuard.accepts(original: original, candidate: original + " " + original))
    }

    func testRejectsChangedNumbers() {
        XCTAssertFalse(TranslationPolishGuard.accepts(
            original: "It sold 100,000 units in 3 days.",
            candidate: "It sold 10,000 units in 3 days."
        ))
    }

    func testIgnoresThousandsSeparatorStyle() {
        XCTAssertTrue(TranslationPolishGuard.accepts(
            original: "Terjual 100,000 unit dalam 3 hari.",
            candidate: "Terjual 100.000 unit hanya dalam 3 hari."
        ))
    }

    func testRejectsAnnouncedOutput() {
        XCTAssertFalse(TranslationPolishGuard.accepts(
            original: original,
            candidate: "Here is the natural version: Saya sangat berterima kasih jika Anda menyiapkan materi sebelum Senin."
        ))
    }

    func testRejectsMultiLineOutputForSingleLineTranslation() {
        XCTAssertFalse(TranslationPolishGuard.accepts(original: original, candidate: "Saya berterima kasih.\nCatatan: ..."))
    }

    func testPolishingIsReportedUnavailableForIndonesian() {
        // Apple's on-device model does not list Indonesian; the UI must not offer polishing for it.
        let availability = TranslationPolisher.availability(forTargetLanguageID: "id")
        XCTAssertNotEqual(availability, .available)
    }
}
