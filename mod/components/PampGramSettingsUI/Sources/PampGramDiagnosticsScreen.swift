import Foundation
import UIKit
import Display
import AccountContext
import PampGramCore

private final class PampGramDiagnosticsViewController: UIViewController {
    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Диагностика"
        self.view.backgroundColor = UIColor.systemBackground

        self.textView.isEditable = false
        self.textView.alwaysBounceVertical = true
        self.textView.font = UIFont.monospacedSystemFont(ofSize: 11.0, weight: .regular)
        self.textView.backgroundColor = UIColor.systemBackground
        self.textView.textColor = UIColor.label
        self.textView.textContainerInset = UIEdgeInsets(top: 12.0, left: 12.0, bottom: 12.0, right: 12.0)
        self.textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.textView.frame = self.view.bounds
        self.view.addSubview(self.textView)

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .done, target: self, action: #selector(self.closePressed))
        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Копировать", style: .plain, target: self, action: #selector(self.copyPressed)),
            UIBarButtonItem(title: "Очистить", style: .plain, target: self, action: #selector(self.clearPressed))
        ]
        self.reload()
    }

    private func reload() {
        self.textView.text = PampGramDiagnostics.shared.dump()
        let length = (self.textView.text as NSString).length
        if length > 0 {
            self.textView.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
        }
    }

    @objc private func closePressed() {
        self.dismiss(animated: true)
    }

    @objc private func copyPressed() {
        UIPasteboard.general.string = self.textView.text
    }

    @objc private func clearPressed() {
        PampGramDiagnostics.shared.clear()
        self.reload()
    }
}

/// "Дополнительно → Диагностика": what the mod's background features (auto-save of one-time
/// media, local message edits) actually did on this device, newest last.
public func pampGramPresentDiagnostics(context: AccountContext) {
    guard let top = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    let navigation = UINavigationController(rootViewController: PampGramDiagnosticsViewController())
    navigation.modalPresentationStyle = .pageSheet
    top.present(navigation, animated: true)
}
