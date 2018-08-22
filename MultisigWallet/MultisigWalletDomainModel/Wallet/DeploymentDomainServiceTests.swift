//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import XCTest
@testable import MultisigWalletDomainModel
import MultisigWalletImplementations
import CommonTestSupport
import BigInt

class BaseDeploymentDomainServiceTests: XCTestCase {

    let eventPublisher = MockEventPublisher()
    let walletRepository = InMemoryWalletRepository()
    let portfolioRepository = InMemorySinglePortfolioRepository()
    let encryptionService = MockEncryptionService1()
    let relayService = MockTransactionRelayService1()
    let notificationService = MockNotificationService1()
    let errorStream = MockErrorStream()
    let nodeService = MockEthereumNodeService1()
    var deploymentService: DeploymentDomainService!
    let accountRepository = InMemoryAccountRepository()
    let eoaRepository = InMemoryExternallyOwnedAccountRepository()
    let system = MockSystem()
    var wallet: Wallet!

    override func setUp() {
        super.setUp()
        deploymentService = DeploymentDomainService(.testConfiguration)
        deploymentService.responseValidator = MockSafeCreationResponseValidator()
        DomainRegistry.put(service: eventPublisher, for: EventPublisher.self)
        DomainRegistry.put(service: walletRepository, for: WalletRepository.self)
        DomainRegistry.put(service: portfolioRepository, for: SinglePortfolioRepository.self)
        DomainRegistry.put(service: encryptionService, for: EncryptionDomainService.self)
        DomainRegistry.put(service: relayService, for: TransactionRelayDomainService.self)
        DomainRegistry.put(service: errorStream, for: ErrorStream.self)
        DomainRegistry.put(service: nodeService, for: EthereumNodeDomainService.self)
        DomainRegistry.put(service: accountRepository, for: AccountRepository.self)
        DomainRegistry.put(service: notificationService, for: NotificationDomainService.self)
        DomainRegistry.put(service: eoaRepository, for: ExternallyOwnedAccountRepository.self)
        DomainRegistry.put(service: system, for: System.self)
    }

}

class DeployingWalletTests: BaseDeploymentDomainServiceTests {

    override func setUp() {
        super.setUp()
        eventPublisher.addFilter(DeploymentStarted.self)
    }

    func test_whenInDraft_thenFetchesCreationTransactionData() {
        givenDraftWalletWithAllOwners()
        relayService.expect_createSafeCreationTransaction(.testRequest(wallet, encryptionService), .testResponse)
        deploymentService.start()
        relayService.verify()
    }

    func test_whenFetchedTransactionData_thenUpdatesAddressAndFee() {
        givenDraftWalletWithAllOwners()
        let response = SafeCreationTransactionRequest.Response.testResponse
        relayService.expect_createSafeCreationTransaction(.testRequest(wallet, encryptionService), response)
        deploymentService.start()
        wallet = walletRepository.findByID(wallet.id)!
        XCTAssertEqual(wallet.address, response.walletAddress)
        XCTAssertEqual(wallet.minimumDeploymentTransactionAmount, response.deploymentFee)
    }

    func test_whenCreationTransactionThrows_thenErrorPosted() {
        givenDraftWalletWithAllOwners()
        relayService.expect_createSafeCreationTransaction_throw(TestError.error)
        assertThrows(TestError.error)
    }

    func test_whenCreationTransactionThrows_thenCancelsDeployment() {
        givenDraftWalletWithAllOwners()
        relayService.expect_createSafeCreationTransaction_throw(TestError.error)
        assertDeploymentCancelled()
    }

}

class ConfiguredWalletTests: BaseDeploymentDomainServiceTests {

    override func setUp() {
        super.setUp()
        eventPublisher.addFilter(WalletConfigured.self)
    }

    func test_whenWalletConfigured_thenObservesBalance() {
        givenConfiguredWallet()
        nodeService.expect_eth_getBalance(account: Address.safeAddress, balance: 100)
        deploymentService.start()
        nodeService.verify()
        let account = DomainRegistry.accountRepository.find(
            id: AccountID(tokenID: Token.Ether.id, walletID: wallet.id), walletID: wallet.id)!
        XCTAssertEqual(account.balance, 100)
    }

    func test_whenNotEnoughFundsAtFirst_thenRepeatsUntilHasFunds() {
        givenConfiguredWallet()
        nodeService.expect_eth_getBalance(account: Address.safeAddress, balance: 50)
        nodeService.expect_eth_getBalance(account: Address.safeAddress, balance: 100)
        deploymentService.start()
        nodeService.verify()
    }

    func test_whenObservingBalanceFails_thenErrorPosted() {
        givenConfiguredWallet()
        nodeService.expect_eth_getBalance_throw(TestError.error)
        assertThrows(TestError.error)
    }

    func test_whenObservingBalanceFails_thenCancels() {
        givenConfiguredWallet()
        nodeService.expect_eth_getBalance_throw(TestError.error)
        deploymentService.start()
        assertDeploymentCancelled()
    }

}

class DeploymentFundedTests: BaseDeploymentDomainServiceTests {

    override func setUp() {
        super.setUp()
        eventPublisher.addFilter(DeploymentFunded.self)
    }

    func test_whenFunded_thenNotifiesRelayService() {
        givenFundedWallet()
        relayService.expect_startSafeCreation(address: wallet.address!)
        deploymentService.start()
        relayService.verify()
    }

    func test_whenFailsToNotifyService_thenHandlesError() {
        givenFundedWallet()
        relayService.expect_startSafeCreation_throw(TestError.error)
        assertThrows(TestError.error)
    }

    func test_whenFailsToNotifyService_thenCancels() {
        givenFundedWallet()
        relayService.expect_startSafeCreation_throw(TestError.error)
        deploymentService.start()
        assertDeploymentCancelled()
    }

}

class CreationStartedTests: BaseDeploymentDomainServiceTests {

    let successReceipt = TransactionReceipt(hash: TransactionHash.test1, status: .success)
    let failedReceipt = TransactionReceipt(hash: TransactionHash.test1, status: .failed)

    override func setUp() {
        super.setUp()
        eventPublisher.addFilter(CreationStarted.self)
    }

    func test_whenFunded_thenWaitsForTransaction() {
        givenDeployingWallet(withoutTransaction: true)
        relayService.expect_safeCreationTransactionHash(address: wallet.address!, hash: nil)
        relayService.expect_safeCreationTransactionHash(address: wallet.address!, hash: TransactionHash.test1)
        nodeService.expect_eth_getTransactionReceipt(transaction: TransactionHash.test1, receipt: successReceipt)
        deploymentService.start()
        relayService.verify()
        wallet = DomainRegistry.walletRepository.selectedWallet()!
        XCTAssertEqual(wallet.creationTransactionHash, TransactionHash.test1.value)
    }


    func test_whenTransactionKnown_thenWaitsForItsStatus() {
        givenDeployingWallet()
        nodeService.expect_eth_getTransactionReceipt(transaction: TransactionHash.test1, receipt: successReceipt)
        deploymentService.start()
        relayService.verify()
        nodeService.verify()
        wallet = DomainRegistry.walletRepository.selectedWallet()!
        XCTAssertTrue(wallet.state === wallet.readyToUseState)
    }

    func test_whenTransactionFailed_thenCancels() {
        givenDeployingWallet()
        nodeService.expect_eth_getTransactionReceipt(transaction: TransactionHash.test1, receipt: failedReceipt)
        deploymentService.start()
        assertDeploymentCancelled()
    }

}

class WalletCreatedTests: BaseDeploymentDomainServiceTests {

    override func setUp() {
        super.setUp()
        eventPublisher.addFilter(WalletCreated.self)
    }

    func test_whenCreated_thenNotifiesExtension() {
        givenCreatedWalletWithNotifiedExtension()
        deploymentService.start()
        encryptionService.verify()
        notificationService.verify()
    }

    func test_whenCreated_thenRemovesPaperWallet() {
        givenCreatedWalletWithNotifiedExtension()
        eoaRepository.save(.testAccount(wallet,
                                        role: .paperWallet,
                                        privateKey: .testPrivateKey,
                                        publicKey: .testPublicKey))

        deploymentService.start()
        XCTAssertNil(eoaRepository.find(by: wallet.owner(role: .paperWallet)!.address))
    }

}

class WalletCreationFailedTests: BaseDeploymentDomainServiceTests {

    override func setUp() {
        super.setUp()
        eventPublisher.addFilter(WalletCreationFailed.self)
    }

    func test_whenFailed_thenExits() {
        givenDeployingWallet()
        deploymentService.start()
        system.expect_exit(EXIT_FAILURE)
        wallet.cancel()
        system.verify()
    }

}

// MARK: - Helpers

extension BaseDeploymentDomainServiceTests {

    func givenDraftWalletWithAllOwners() {
        wallet = Wallet(id: walletRepository.nextID(), owner: Address.deviceAddress)
        wallet.addOwner(Wallet.createOwner(address: Address.extensionAddress.value, role: .browserExtension))
        wallet.addOwner(Wallet.createOwner(address: Address.paperWalletAddress.value, role: .paperWallet))
        walletRepository.save(wallet)
        let portfolio = Portfolio(id: portfolioRepository.nextID())
        portfolio.addWallet(wallet.id)
        portfolioRepository.save(portfolio)
        let account = Account(tokenID: Token.Ether.id)
        DomainRegistry.accountRepository.save(account)
    }

    func givenConfiguredWallet() {
        givenDraftWalletWithAllOwners()
        wallet.markReadyToDeploy()
        wallet.startDeployment()
        wallet.changeAddress(Address.safeAddress)
        wallet.updateMinimumTransactionAmount(100)
    }

    func givenFundedWallet() {
        givenConfiguredWallet()
        wallet.proceed()
        let account = DomainRegistry.accountRepository.find(
            id: AccountID(tokenID: Token.Ether.id, walletID: wallet.id), walletID: wallet.id)!
        account.update(newAmount: 100)
        DomainRegistry.accountRepository.save(account)
    }

    func givenDeployingWallet(withoutTransaction: Bool = false) {
        givenFundedWallet()
        wallet.markDeploymentAcceptedByBlockchain()
        if !withoutTransaction {
            wallet.assignCreationTransaction(hash: TransactionHash.test1.value)
        }
        wallet.proceed()
        DomainRegistry.walletRepository.save(wallet)
    }

    func givenCreatedWallet() {
        givenDeployingWallet()
        wallet.proceed()
        walletRepository.save(wallet)
    }

    func givenCreatedWalletWithNotifiedExtension() {
        givenCreatedWallet()
        eoaRepository.save(.testAccount(wallet,
                                        role: .thisDevice,
                                        privateKey: .testPrivateKey,
                                        publicKey: .testPublicKey))
        let message = "safeCreated"
        let request = SendNotificationRequest(message: message,
                                              to: wallet.owner(role: .browserExtension)!.address.value,
                                              from: .testSignature)
        encryptionService.expect_sign(message: "GNO" + message,
                                      privateKey: .testPrivateKey,
                                      signature: .testSignature)
        notificationService.expect_safeCreatedMessage(at: wallet.address!.value, message: message)
        notificationService.expect_send(notificationRequest: request)
    }

    func assertThrows(_ error: Error, line: UInt = #line) {
        errorStream.expect_post(error)
        deploymentService.start()
        errorStream.verify(line: line)
    }

    func assertDeploymentCancelled(line: UInt = #line) {
        wallet = walletRepository.findByID(wallet.id)!
        XCTAssertTrue(wallet.state === wallet.newDraftState, line: line)
    }

}

extension SendNotificationRequest {

    func toString() -> String {
        return try! String(data: JSONEncoder().encode(self), encoding: .utf8)!
    }

}

// MARK: - Fixtures

extension DeploymentDomainServiceConfiguration {
    static let testConfiguration = DeploymentDomainServiceConfiguration(balance: .testParameters,
                                                                        deploymentStatus: .testParameters,
                                                                        transactionStatus: .testParameters)
}

extension DeploymentDomainServiceConfiguration.Parameters {
    static let testParameters = DeploymentDomainServiceConfiguration.Parameters(repeatDelay: 0,
                                                                                retryAttempts: 3,
                                                                                retryDelay: 0)
}

extension SafeCreationTransactionRequest {

    static func testRequest(_ wallet: Wallet, _ encryptionService: EncryptionDomainService) ->
        SafeCreationTransactionRequest {
            return SafeCreationTransactionRequest(owners: wallet.allOwners().map { $0.address },
                                                  confirmationCount: wallet.confirmationCount,
                                                  ecdsaRandomS: encryptionService.ecdsaRandomS())
    }

    func toString() -> String {
        return try! String(data: JSONEncoder().encode(self), encoding: .utf8)!
    }

}

extension SafeCreationTransactionRequest.Response {
    static let testResponse = SafeCreationTransactionRequest.Response(signature: .testSignature,
                                                                      tx: .testTransaction,
                                                                      safe: Address.safeAddress.value,
                                                                      payment: "100")
}


extension SafeCreationTransactionRequest.Response.Signature {
    static let testSignature = SafeCreationTransactionRequest.Response.Signature(r: "0", s: "0", v: "27")
}

extension SafeCreationTransactionRequest.Response.Transaction {
    static let testTransaction = SafeCreationTransactionRequest.Response.Transaction(from: Address.testAccount1.value,
                                                                                     value: 100,
                                                                                     data: "0x01",
                                                                                     gas: "100",
                                                                                     gasPrice: "100",
                                                                                     nonce: 0)
}

extension ExternallyOwnedAccount {
    static func testAccount(_ wallet: Wallet, role: OwnerRole, privateKey: PrivateKey, publicKey: PublicKey)
        -> ExternallyOwnedAccount {
            return ExternallyOwnedAccount(address: wallet.owner(role: role)!.address,
                                          mnemonic: Mnemonic(words: ["one", "two"]),
                                          privateKey: privateKey,
                                          publicKey: publicKey)
    }
}

extension PrivateKey {
    static let testPrivateKey = PrivateKey(data: Data(repeating: 3, count: 32))
}

extension PublicKey {
    static let testPublicKey = PublicKey(data: Data(repeating: 5, count: 32))
}

extension EthSignature {
    static let testSignature = EthSignature(r: "1", s: "2", v: 27)
}
