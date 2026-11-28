// The fingerprint the apps show matches what `hiboss boss keys` prints for the same key id.
// Exports BossKeyTextTests. Dependencies: XCTest, HibossKit SecureEnclaveMessageSigner.

import Foundation
import XCTest
@testable import HibossKit

final class BossKeyTextTests: XCTestCase {
    func testFingerprintIsTheFirstSixteenKeyIdCharactersInFours() throws {
        let json = #"{"keyRepresentation":"AAAA","keyID":"Ab3dEf7hIj1lMn5pQr9t","bossID":"boss-1","clientKind":"ios"}"#
        let signer = try JSONDecoder().decode(SecureEnclaveMessageSigner.self, from: Data(json.utf8))
        XCTAssertEqual(signer.fingerprint, "Ab3d-Ef7h-Ij1l-Mn5p")
    }
}
