// Verifies APNs routing from embedded provisioning profile entitlements.
// Dependencies: XCTest and the pure PushEnvironment resolver.

import XCTest
@testable import HiBoss

final class PushEnvironmentTests: XCTestCase {
    func testDevelopmentProfileUsesSandboxRegardlessOfBuildConfiguration() throws {
        let profile = try profile(environment: "development")
        XCTAssertEqual(PushEnvironment.resolve(profile: profile, isSimulator: false), "sandbox")
    }

    func testProductionProfileOverridesSimulatorFallback() throws {
        let profile = try profile(environment: "production")
        XCTAssertEqual(PushEnvironment.resolve(profile: profile, isSimulator: false), "production")
        XCTAssertEqual(PushEnvironment.resolve(profile: profile, isSimulator: true), "production")
    }

    func testMissingProfileUsesPlatformFallback() {
        XCTAssertEqual(PushEnvironment.resolve(profile: nil, isSimulator: false), "production")
        XCTAssertEqual(PushEnvironment.resolve(profile: nil, isSimulator: true), "sandbox")
    }

    func testUnparseableProfileUsesPlatformFallback() {
        for bytes in [Data(), Data([0xff, 0x00, 0x80]), Data("<plist>broken</plist>".utf8)] {
            XCTAssertEqual(PushEnvironment.resolve(profile: bytes, isSimulator: false), "production")
            XCTAssertEqual(PushEnvironment.resolve(profile: bytes, isSimulator: true), "sandbox")
        }
    }

    func testMissingOrUnknownEntitlementUsesPlatformFallback() throws {
        for environment in ["unknown", ""] {
            let bytes = try profile(environment: environment)
            XCTAssertEqual(PushEnvironment.resolve(profile: bytes, isSimulator: false), "production")
        }
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: ["Entitlements": [:]], format: .xml, options: 0)
        XCTAssertEqual(PushEnvironment.resolve(profile: bytes, isSimulator: false), "production")
    }

    private func profile(environment: String) throws -> Data {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["Entitlements": ["aps-environment": environment]],
            format: .xml, options: 0)
        // Binary CMS bytes surround the XML payload in embedded.mobileprovision.
        return Data([0x30, 0x82, 0xff, 0x00]) + plist + Data([0x00, 0xfe, 0x81])
    }
}
