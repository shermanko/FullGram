import Foundation
import UIKit
import ObjectiveC
import LocalAuthentication
import Display
import TelegramCore

final class FullGramChatLockView: UIView {
    var unlock: (() -> Void)?
    var isAuthenticating = false

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

private var fullGramLockObserverKey: UInt8 = 0

private final class FullGramChatLockObserverToken {
    private var tokens: [NSObjectProtocol] = []

    init(controller: ChatControllerImpl) {
        let handler: (Notification) -> Void = { [weak controller] _ in
            controller?.fullGramApplyChatLock()
        }
        self.tokens.append(
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: handler)
        )
        self.tokens.append(
            NotificationCenter.default.addObserver(forName: FullGramChatPrivacy.didRelockNotification, object: nil, queue: .main, using: handler)
        )
    }

    deinit {
        for token in self.tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

extension ChatControllerImpl {
    private func fullGramEnsureLockObserver() {
        if objc_getAssociatedObject(self, &fullGramLockObserverKey) == nil {
            let token = FullGramChatLockObserverToken(controller: self)
            objc_setAssociatedObject(self, &fullGramLockObserverKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func fullGramApplyChatLock() {
        self.fullGramEnsureLockObserver()
        guard let peerId = self.chatLocation.peerId else { return }
        let value = peerId.toInt64()
        guard FullGramChatPrivacy.isLocked(value), !FullGramChatPrivacy.isUnlocked(value) else { return }

        if let existing = self.view.subviews.first(where: { $0 is FullGramChatLockView }) as? FullGramChatLockView {
            existing.frame = self.view.bounds
            self.view.bringSubviewToFront(existing)
            return
        }

        let lockView = FullGramChatLockView(frame: self.view.bounds)
        lockView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(lockView)
        self.view.bringSubviewToFront(lockView)

        let authenticate = { [weak self, weak lockView] in
            guard let lockView, !lockView.isAuthenticating else { return }
            lockView.isAuthenticating = true
            let context = LAContext()
            let ru = Locale.preferredLanguages.first?.hasPrefix("ru") == true
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                lockView.isAuthenticating = false
                FullGramChatPrivacy.markUnlocked(value)
                lockView.removeFromSuperview()
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: ru ? "Откройте заблокированный чат" : "Open the locked chat", reply: { success, _ in
                DispatchQueue.main.async {
                    lockView.isAuthenticating = false
                    if success {
                        FullGramChatPrivacy.markUnlocked(value)
                        UIView.animate(withDuration: 0.2, animations: { lockView.alpha = 0.0 }, completion: { _ in lockView.removeFromSuperview() })
                    } else if let self {
                        if let nav = self.navigationController as? NavigationController {
                            nav.filterController(self, animated: true)
                        } else {
                            let _ = self.navigationController?.popViewController(animated: true)
                        }
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
