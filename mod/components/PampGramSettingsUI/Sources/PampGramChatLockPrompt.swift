import Foundation
import UIKit
import Display
import AccountContext

private func pampGramPresentChatLockAlert(presenter: UIViewController, pin: String, wrongAttempt: Bool, completion: @escaping () -> Void) {
    let alert = UIAlertController(
        title: "Чат заблокирован",
        message: wrongAttempt ? "Неверный PIN-код. Попробуйте ещё раз." : "Введите PIN-код, чтобы открыть чат.",
        preferredStyle: .alert
    )
    alert.addTextField { field in
        field.isSecureTextEntry = true
        field.keyboardType = .numberPad
        field.placeholder = "PIN-код"
    }
    alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    alert.addAction(UIAlertAction(title: "Открыть", style: .default, handler: { [weak alert] _ in
        let entered = alert?.textFields?.first?.text ?? ""
        if entered == pin {
            completion()
        } else {
            pampGramPresentChatLockAlert(presenter: presenter, pin: pin, wrongAttempt: true, completion: completion)
        }
    }))
    presenter.present(alert, animated: true)
}

/// "Блокировка чатов": asks for the chat-lock PIN before a locked chat opens. Telegram 13.x's own
/// PasscodeSetupController no longer takes an arbitrary PIN to check against (it works on the
/// app passcode only), so the prompt is the mod's own.
public func pampGramPresentChatLockPrompt(navigationController: NavigationController, pin: String, completion: @escaping () -> Void) {
    let presenter: UIViewController = navigationController.topViewController ?? navigationController
    pampGramPresentChatLockAlert(presenter: presenter, pin: pin, wrongAttempt: false, completion: completion)
}
