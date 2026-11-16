import Foundation
import UIKit
import LocalAuthentication
import Display
import TelegramCore

final class FullGramChatLockView: UIView {
    var unlock: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        blur.frame = self.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(blur)

        let icon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40.0, weight: .medium)))
        icon.tintColor = .label
        let button = UIButton(type: .system)
        let ru = Locale.preferredLanguages.first?.hasPrefix("ru") == true
        button.setTitle(ru ? "Разблокировать" : "Unlock", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        button.addTarget(self, action: #selector(self.unlockPressed), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, button])
        stack.axis = .vertical
        stack.spacing = 16.0
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func unlockPressed() {
        self.unlock?()
    }
}

extension ChatControllerImpl {
    func fullGramApplyChatLock() {
        guard let peerId = self.chatLocation.peerId else { return }
        let value = peerId.toInt64()
        guard FullGramChatPrivacy.isLocked(value), !FullGramChatPrivacy.isUnlocked(value) else { return }
        if self.view.subviews.contains(where: { $0 is FullGramChatLockView }) {
            return
        }
        let lockView = FullGramChatLockView(frame: self.view.bounds)
        lockView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(lockView)
        let authenticate = { [weak self, weak lockView] in
            let context = LAContext()
            let ru = Locale.preferredLanguages.first?.hasPrefix("ru") == true
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                FullGramChatPrivacy.markUnlocked(value)
                lockView?.removeFromSuperview()
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: ru ? "Откройте заблокированный чат" : "Open the locked chat", reply: { success, _ in
                DispatchQueue.main.async {
                    if success {
                        FullGramChatPrivacy.markUnlocked(value)
                        UIView.animate(withDuration: 0.2, animations: { lockView?.alpha = 0.0 }, completion: { _ in lockView?.removeFromSuperview() })
                    } else if let self {
                        let _ = self.navigationController?.popViewController(animated: true)
                    }
                }
            })
        }
        lockView.unlock = authenticate
        DispatchQueue.main.async {
            authenticate()
        }
    }
}
