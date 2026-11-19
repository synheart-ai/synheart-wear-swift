import XCTest
@testable import SynheartWear

final class VendorAuthorizationURLTests: XCTestCase {
    func testAcceptsHttps() throws {
        let url = try vendorAuthorizationURL("https://cloud.ouraring.com/oauth/authorize?client_id=x&state=s")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "cloud.ouraring.com")
    }

    func testSchemeIsCaseInsensitive() throws {
        XCTAssertNoThrow(try vendorAuthorizationURL("HTTPS://www.fitbit.com/oauth2/authorize"))
    }

    func testRejectsPlainHttp() {
        XCTAssertThrowsError(try vendorAuthorizationURL("http://cloud.ouraring.com/oauth/authorize"))
    }

    func testRejectsOtherSchemesAndRelativePaths() {
        for bad in ["javascript:alert(1)", "myapp://callback", "/oauth/authorize", "https://", "", "not a url"] {
            XCTAssertThrowsError(try vendorAuthorizationURL(bad), bad)
        }
    }
}
