//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import UIKit
import SafeUIKit
import Common
import MultisigWalletApplication

protocol RecoverRecoveryFeeViewControllerDelegate: class {
    func recoverRecoveryFeeViewControllerDidCancel()
    func recoverRecoveryFeeViewControllerDidBecomeReadyToSubmit()
}

/// Estimates recovery transaction and if balance is not enough, shows the needed amount to transfer.
/// If the balance is enough, it will call the delegate and stop reacting to the update events.
class RecoverRecoveryFeeViewController: CardViewController {

    let feeRequestView = FeeRequestView()
    let addressDetailView = AddressDetailView()
    var retryItem: UIBarButtonItem!
    weak var delegate: RecoverRecoveryFeeViewControllerDelegate?

    /// Flag to remember that transaction became ready for submission.
    /// Controller will then ignore all other update events
    var isFinished: Bool = false

    enum Strings {

        static let title = LocalizedString("recover_safe_title", comment: "Create Safe")
        static let subtitle = LocalizedString("insufficient_funds", comment: "Insufficient funds header.")
        static let subtitleDetail = LocalizedString("recovering_requires_fee", comment: "Explanation text.")
        static let amountReceived = LocalizedString("safe_balance", comment: "Safe balance")
    }


    static func create(delegate: RecoverRecoveryFeeViewControllerDelegate) -> RecoverRecoveryFeeViewController {
        let controller = RecoverRecoveryFeeViewController(nibName: String(describing: CardViewController.self),
                                                          bundle: Bundle(for: CardViewController.self))
        controller.delegate = delegate
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        embed(view: feeRequestView, inCardSubview: cardHeaderView)
        embed(view: addressDetailView, inCardSubview: cardBodyView)
        footerButton.isHidden = true
        scrollView.isHidden = true

        retryItem = .refreshButton(target: self, action: #selector(retry))

        navigationItem.leftBarButtonItem = .cancelButton(target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = retryItem
        addressDetailView.shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)

        start()
    }

    // TODO: from creation process tracker

    func start() {
        // show loading state
        navigationItem.titleView = LoadingTitleView()
        retryItem.isEnabled = false

        // start the estimation
        DispatchQueue.global().async {
            ApplicationServiceRegistry.recoveryService
                .createRecoveryTransaction(subscriber: self) { [weak self] error in
                    guard let `self` = self else { return }
                    DispatchQueue.main.async {
                        self.show(error: error)
                    }
            }
            ApplicationServiceRegistry.recoveryService.observeBalance(subscriber: self)
        }
    }

    func show(error: Error) {
        navigationItem.titleView = nil

        let canRetry = isRetriableError(error)
        retryItem.isEnabled = canRetry

        let message = error.localizedDescription
        let controller = UIAlertController.operationFailed(message: message) { [unowned self] in
            if !canRetry {
                self.delegate?.recoverRecoveryFeeViewControllerDidCancel()
            }
        }
        present(controller, animated: true)
    }

    func isRetriableError(_ error: Error) -> Bool {
        switch error {
        case let nsError as NSError where nsError.domain == NSURLErrorDomain:
            fallthrough
        case WalletApplicationServiceError.clientError,
             WalletApplicationServiceError.networkError,
             EthereumApplicationService.Error.clientError,
             EthereumApplicationService.Error.networkError:
            return true
        default:
            return false
        }
    }

    // till this point from creation process tracker

    @objc func cancel() {
        DispatchQueue.global().async {
            ApplicationServiceRegistry.recoveryService.cancelRecovery()
        }
        delegate?.recoverRecoveryFeeViewControllerDidCancel()
    }

    @objc func share() {
        guard let address = ApplicationServiceRegistry.walletService.selectedWalletAddress else { return }
        let activityController = UIActivityViewController(activityItems: [address], applicationActivities: nil)
        self.present(activityController, animated: true)
    }

    @objc func retry() {
        start()
    }

    func update() {
        if isFinished { return }
        if ApplicationServiceRegistry.recoveryService.isRecoveryTransactionReadyToSubmit() {
            isFinished = true
            delegate?.recoverRecoveryFeeViewControllerDidBecomeReadyToSubmit()
            return
        }
        guard let tx = ApplicationServiceRegistry.recoveryService.recoveryTransaction() else { return }

        navigationItem.titleView = nil
        navigationItem.title = Strings.title

        setSubtitle(Strings.subtitle, showError: true)
        setSubtitleDetail(Strings.subtitleDetail)

        feeRequestView.amountReceivedLabel.text = Strings.amountReceived
        feeRequestView.remainderTextLabel.text = FeeRequestView.Strings.sendRemainderRequest

        setFootnoteTokenCode(tx.feeTokenData.code)

        addressDetailView.address = tx.sender

        let balance = (ApplicationServiceRegistry
            .walletService.accountBalance(tokenID: BaseID(tx.feeTokenData.address)) ?? 0)
        feeRequestView.amountReceivedAmountLabel.amount = tx.feeTokenData.withBalance(balance)
        feeRequestView.amountNeededAmountLabel.amount = tx.feeTokenData.withNonNegativeBalance()
        let remaining = (tx.feeTokenData.withNonNegativeBalance().balance ?? 0) - balance
        feeRequestView.remainderAmountLabel.amount = tx.feeTokenData.withBalance(remaining)

        scrollView.isHidden = false
    }

    func setFootnoteTokenCode(_ code: String) {
        let template = LocalizedString("please_send_x", comment: "Please send %")
        addressDetailView.footnoteLabel.text = String(format: template, code)
    }

    override func showNetworkFeeInfo() {
        present(UIAlertController.recoveryFee(), animated: true, completion: nil)
    }

}


extension RecoverRecoveryFeeViewController: EventSubscriber {

    public func notify() {
        DispatchQueue.main.async(execute: update)
    }

}
