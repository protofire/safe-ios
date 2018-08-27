//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import XCTest
@testable import safe
import IdentityAccessImplementations
import IdentityAccessDomainModel
import SafeAppUI
import CommonImplementations
import CommonTestSupport
import MultisigWalletDomainModel
import MultisigWalletImplementations

class AppDelegateTests: XCTestCase {

    // swiftlint:disable:next weak_delegate
    let appDelegate = AppDelegate()
    let mockSyncService = MockSynchronisationService()

    func test_whenAppBecomesActive_thenCallsCoordinator() {
        let coordinator = MockCoordinator()
        appDelegate.coordinator = coordinator
        appDelegate.applicationWillEnterForeground(UIApplication.shared)
        XCTAssertTrue(coordinator.didBecomeActive)
    }

    func test_whenAppBecomesActive_thenSyncronises() {
        MultisigWalletDomainModel.DomainRegistry.put(service: mockSyncService, for: SynchronisationDomainService.self)
        XCTAssertFalse(mockSyncService.didSync)
        appDelegate.applicationWillEnterForeground(UIApplication.shared)
        delay(0.5)
        XCTAssertTrue(mockSyncService.didSync)
    }

    func test_bundleHasRequiredProperties() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription"))
    }

    func test_mainBundleContainsLoggerKeys() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: LogServiceLogLevelKey))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: LogServiceEnabledLoggersKey))
    }

    func test_defaultValues() {
        XCTAssertNotNil(DomainRegistry.biometricAuthenticationService)
        XCTAssertNotNil(DomainRegistry.userRepository)
        XCTAssertNotNil(DomainRegistry.identityService)
        XCTAssertNotNil(DomainRegistry.gatekeeperRepository)
        XCTAssertNotNil(DomainRegistry.gatekeeperRepository.gatekeeper())
    }

    func test_whenAppEnteresForeground_thenItInvalidatesAppIconBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 1
        appDelegate.applicationWillEnterForeground(UIApplication.shared)
        XCTAssertEqual(UIApplication.shared.applicationIconBadgeNumber, 0)
    }

}

class MockCoordinator: AppFlowCoordinator {

    var didBecomeActive = false

    override func appEntersForeground() {
        didBecomeActive = true
    }

    override func setUp() {
        super.setUp()
        UIApplication.shared.keyWindow?.rootViewController = UIViewController()
    }

}
