//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import UIKit
import SafeUIKit

final class ContractUpgradeHeaderView: UITableViewHeaderFooterView {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var updateButton: StandardButton!

    var onUpgrade: (() -> Void)?

    enum Strings {
        static let title = LocalizedString("upgrade_required", comment: "Security upgrade required")
        static let description = LocalizedString("security_upgrade_required", comment: "Update required description")
        static let upgradeNow = LocalizedString("upgrade_now", comment: "Upgrade now")
    }

    @IBAction func update(_ sender: Any) {
        onUpgrade?()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.text = Strings.title
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = ColorName.darkBlue.color
        descriptionLabel.text = Strings.description
        descriptionLabel.font = UIFont.systemFont(ofSize: 17)
        descriptionLabel.textColor = ColorName.darkGrey.color
        updateButton.style = .plain
        updateButton.setTitle(Strings.upgradeNow, for: .normal)
    }

}
