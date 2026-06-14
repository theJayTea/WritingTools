import XCTest
@testable import WritingTools

final class AppThemeSurfacePolicyTests: XCTestCase {
    func testStandardThemeUsesNativeSolidAuxiliarySurfaces() {
        XCTAssertFalse(AppTheme.standard.usesThemedAuxiliarySurfaces)
    }

    func testNonStandardThemesExtendIntoAuxiliarySurfaces() {
        XCTAssertTrue(AppTheme.gradient.usesThemedAuxiliarySurfaces)
        XCTAssertTrue(AppTheme.glass.usesThemedAuxiliarySurfaces)
        XCTAssertTrue(AppTheme.oled.usesThemedAuxiliarySurfaces)
    }
}
