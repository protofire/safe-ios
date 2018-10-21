//
//  Copyright © 2018 Gnosis Ltd. All rights reserved.
//

import UIKit

@objc public protocol VerifiableInputDelegate: class {
    func verifiableInputDidReturn(_ verifiableInput: VerifiableInput)
    @objc optional func verifiableInputDidBeginEditing(_ verifiableInput: VerifiableInput)
    @objc optional func verifiableInputDidEndEditing(_ verifiableInput: VerifiableInput)
}

public class VerifiableInput: UIView {

    @IBOutlet var wrapperView: UIView!
    @IBOutlet public private(set) weak var textInput: TextInput!
    @IBOutlet weak var stackView: UIStackView!

    public weak var delegate: VerifiableInputDelegate?
    /// Indicates whether the view has user input focus
    public private(set) var isActive: Bool = false
    private static let shakeAnimationKey = "shake"

    private var allRules: [RuleLabel] {
        return stackView.arrangedSubviews.compactMap { $0 as? RuleLabel }
    }

    public var isValid: Bool {
        return allRules.reduce(true) { $0 && $1.status == .success }
    }

    public var showErrorsOnly: Bool = false

    public var maxLength: Int = Int.max

    /// When setting this property textInput.text value is formatted and validated.
    public var text: String? {
        get {
            return textInput.text
        }
        set {
            if newValue != nil {
                textInput.text = String(newValue!.prefix(maxLength))
                validateRules(for: textInput.text!)
            } else {
                textInput.text = nil
            }
        }
    }

    public var isEnabled: Bool {
        get { return textInput.isEnabled }
        set { textInput.isEnabled = newValue }
    }

    public var isSecure: Bool {
        get { return textInput.isSecureTextEntry }
        set { textInput.isSecureTextEntry = newValue }
    }

    public var isShaking: Bool {
        return layer.animation(forKey: VerifiableInput.shakeAnimationKey) != nil
    }

    public var isDimmed: Bool {
        get { return textInput.isDimmed }
        set { textInput.isDimmed = newValue }
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public override func awakeFromNib() {
        super.awakeFromNib()
        commonInit()
    }

    private func commonInit() {
        loadContentsFromNib()
        backgroundColor = .clear
        wrapperView.backgroundColor = .clear
        textInput.delegate = self
        textInput.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    }

    private func loadContentsFromNib() {
        safeUIKit_loadFromNib(forClass: VerifiableInput.self)
        self.heightAnchor.constraint(equalTo: stackView.heightAnchor).isActive = true
        wrapperView.heightAnchor.constraint(equalTo: stackView.heightAnchor).isActive = true
        pinWrapperToSelf()
    }

    private func pinWrapperToSelf() {
        NSLayoutConstraint.activate([
            wrapperView.leadingAnchor.constraint(equalTo: leadingAnchor),
            wrapperView.trailingAnchor.constraint(equalTo: trailingAnchor),
            wrapperView.topAnchor.constraint(equalTo: topAnchor)])
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
    }

    public func addRule(_ localizedDescription: String,
                        identifier: String? = nil,
                        validation: ((String) -> Bool)? = nil) {
        let ruleLabel = RuleLabel(text: localizedDescription, rule: validation)
        ruleLabel.accessibilityIdentifier = identifier
        hideRuleIfNeeded(ruleLabel)
        stackView.addArrangedSubview(ruleLabel)
    }

    public override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
        isActive = textInput.becomeFirstResponder()
        return isActive
    }

    public func shake() {
        layer.add(CABasicAnimation.shake(center: center), forKey: VerifiableInput.shakeAnimationKey)
    }

    @objc private func textChanged(_ sender: Any) {
        text = textInput.text // validation
    }

    func validateRules(for text: String) {
        allRules.forEach {
            $0.validate(text)
            hideRuleIfNeeded($0)
        }
    }

}

extension VerifiableInput: UITextFieldDelegate {

    public func textField(_ textField: UITextField,
                          shouldChangeCharactersIn range: NSRange,
                          replacementString string: String) -> Bool {
        let oldText = (textField.text ?? "") as NSString
        let newText = oldText.replacingCharacters(in: range, with: string)
        guard !newText.isEmpty else {
            resetRules()
            return true
        }
        validateRules(for: newText)
        return true
    }

    public func textFieldShouldClear(_ textField: UITextField) -> Bool {
        resetRules()
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let shouldReturn = isValid
        if shouldReturn {
            delegate?.verifiableInputDidReturn(self)
        } else {
            shake()
        }
        return shouldReturn
    }

    public func textFieldDidBeginEditing(_ textField: UITextField) {
        delegate?.verifiableInputDidBeginEditing?(self)
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
        delegate?.verifiableInputDidEndEditing?(self)
    }

    private func resetRules() {
        allRules.forEach {
            $0.reset()
            hideRuleIfNeeded($0)
        }
    }

    private func hideRuleIfNeeded(_ rule: RuleLabel) {
        rule.isHidden = showErrorsOnly ? rule.status != .error : false
    }

}
