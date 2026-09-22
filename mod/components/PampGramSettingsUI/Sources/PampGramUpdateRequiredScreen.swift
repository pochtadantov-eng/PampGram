import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import PampGramCore

/// The screen shown instead of PampGram's real content once the admin has raised the server's
/// minimum build number past this install's own `PampGramSubscriptionAPI.currentBuildVersion` —
/// see that constant's doc for why this can retire a build that's already sitting on someone's
/// device. Two ways out: "Назад" just closes this screen (nothing was ever opened underneath,
/// same reasoning as `PampGramBannedScreen`'s "Закрыть"), "Обновить" opens a chat with the
/// owner with a ready-made request for the new build.
private final class PampGramUpdateRequiredViewController: UIViewController {
    private let onUpdate: () -> Void

    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let updateButton = UIButton(type: .system)

    init(onUpdate: @escaping () -> Void) {
        self.onUpdate = onUpdate
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
        self.isModalInPresentation = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(rgb: 0x0e0e14)

        self.iconContainer.backgroundColor = UIColor(rgb: 0x8e44ec).withAlphaComponent(0.15)
        self.iconContainer.layer.cornerRadius = 44.0
        self.view.addSubview(self.iconContainer)

        self.iconImageView.image = UIImage(systemName: "arrow.triangle.2.circlepath")?.withRenderingMode(.alwaysTemplate)
        self.iconImageView.tintColor = UIColor(rgb: 0x8e44ec)
        self.iconImageView.contentMode = .scaleAspectFit
        self.iconContainer.addSubview(self.iconImageView)

        self.titleLabel.text = "Вышло новое обновление"
        self.titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.view.addSubview(self.titleLabel)

        self.bodyLabel.text = "Новая версия уже вышла — либо вот-вот выйдет. Эта сборка временно недоступна: функции этого раздела отключены до обновления. Дождитесь новой версии и получите её у владельца."
        self.bodyLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.bodyLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.bodyLabel.textAlignment = .center
        self.bodyLabel.numberOfLines = 0
        self.view.addSubview(self.bodyLabel)

        self.backButton.setTitle("Назад", for: .normal)
        self.backButton.setTitleColor(.white, for: .normal)
        self.backButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.backButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.backButton.layer.cornerRadius = 12.0
        self.backButton.addTarget(self, action: #selector(self.backPressed), for: .touchUpInside)
        self.view.addSubview(self.backButton)

        self.updateButton.setTitle("Обновить", for: .normal)
        self.updateButton.setTitleColor(.white, for: .normal)
        self.updateButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.updateButton.backgroundColor = UIColor(rgb: 0x8e44ec)
        self.updateButton.layer.cornerRadius = 12.0
        self.updateButton.addTarget(self, action: #selector(self.updatePressed), for: .touchUpInside)
        self.view.addSubview(self.updateButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let centerY = self.view.bounds.height * 0.4

        let containerSide: CGFloat = 88.0
        self.iconContainer.frame = CGRect(x: (width - containerSide) / 2.0, y: centerY - containerSide - 24.0, width: containerSide, height: containerSide)
        let iconSide: CGFloat = 40.0
        self.iconImageView.frame = CGRect(x: (containerSide - iconSide) / 2.0, y: (containerSide - iconSide) / 2.0, width: iconSide, height: iconSide)

        let textWidth = min(300.0, width - 48.0)
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.titleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.iconContainer.frame.maxY + 24.0, width: textWidth, height: titleSize.height)

        let bodySize = self.bodyLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.bodyLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.titleLabel.frame.maxY + 12.0, width: textWidth, height: bodySize.height)

        let buttonsWidth = min(340.0, width - 48.0)
        let buttonHeight: CGFloat = 50.0
        let buttonSpacing: CGFloat = 12.0
        let buttonWidth = (buttonsWidth - buttonSpacing) / 2.0
        let buttonsY = self.view.bounds.height - self.view.safeAreaInsets.bottom - buttonHeight - 32.0
        self.backButton.frame = CGRect(x: (width - buttonsWidth) / 2.0, y: buttonsY, width: buttonWidth, height: buttonHeight)
        self.updateButton.frame = CGRect(x: self.backButton.frame.maxX + buttonSpacing, y: buttonsY, width: buttonWidth, height: buttonHeight)
    }

    @objc private func backPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func updatePressed() {
        self.dismiss(animated: true, completion: { [weak self] in
            self?.onUpdate()
        })
    }
}

public func pampGramPresentUpdateRequiredScreen(context: AccountContext) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    presentingController.present(PampGramUpdateRequiredViewController(onUpdate: {
        pampGramOpenUpdateRequestChat(context: context)
    }), animated: true, completion: nil)
}

/// The mod owner's own Telegram account — where "Обновить" sends someone waiting on a retired
/// build. Resolved by username each time rather than cached: this is the one place PampGram
/// ever opens a real chat with a real message draft pre-filled, so it goes through the same
/// resolve-then-navigate path Telegram's own `tg://` message links use (see
/// `OpenResolvedUrl.swift`'s `.messageLink` case), not a special-cased shortcut.
private func pampGramOpenUpdateRequestChat(context: AccountContext) {
    guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return
    }
    let _ = (context.engine.peers.resolvePeerByName(name: "Claps228", referrer: nil)
    |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
        guard case let .result(peer) = result else {
            return .complete()
        }
        return .single(peer)
    }
    |> deliverOnMainQueue).startStandalone(next: { peer in
        guard let peer else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
            navigationController: navigationController,
            context: context,
            chatLocation: .peer(peer),
            updateTextInputState: ChatTextInputState(inputText: NSAttributedString(string: "Здравствуйте! Хочу получить новую версию мода, ожидаю обновление.")),
            activateInput: .text,
            keepStack: .always
        ))
    })
}
