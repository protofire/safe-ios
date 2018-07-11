//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import MultisigWalletDomainModel
import Foundation
import CommonTestSupport
import Common

public final class MockNotificationService: NotificationDomainService {

    public var didPair = false
    public var shouldThrow = false
    public var shouldThrowNetworkError = false
    public var shouldThrowValidationFailedError = false
    public var delay: TimeInterval
    public var sentMessages: [String] = []

    public init(delay: TimeInterval = 0) {
        self.delay = delay
    }

    public func pair(pairingRequest: PairingRequest) throws {
        Timer.wait(delay)
        if shouldThrowNetworkError {
            throw JSONHTTPClient.Error.networkRequestFailed(URLRequest(url: URL(string: "http://test.url")!), nil, nil)
        }
        if shouldThrowValidationFailedError {
            throw NotificationDomainServiceError.validationFailed
        }
        if shouldThrow { throw TestError.error }
        didPair = true
    }

    public func send(message: String, to address: String, from signature: EthSignature) throws {
        sentMessages.append("to:\(address) msg:\(message)")
    }

    public func safeCreatedMessage(at address: String) -> String {
        return "SafeCreatedMessage_\(address)"
    }

}
