import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

/// One row of the feature list below the PampGram logo — a colored icon square, a bold title
/// and a one-line description. Mirrors the layout used by pretty much every paywall of this
/// kind (icon + title + description on a rounded dark card); nothing here is copied text or
/// artwork from any specific app, only PampGram's own real PRO-gated features.
private struct PampGramPremiumFeature {
    let systemImageName: String
    let color: UIColor
    let title: String
    let subtitle: String
}

private let pampGramPremiumFeatures: [PampGramPremiumFeature] = [
    PampGramPremiumFeature(systemImageName: "eye.slash.fill", color: UIColor(rgb: 0x34c759), title: "Ghost-режим", subtitle: "Скрывай «в сети», «печатает» и прочтения — плюс автооффлайн, когда не пишешь сам."),
    PampGramPremiumFeature(systemImageName: "waveform", color: UIColor(rgb: 0x3b82f6), title: "Изменение голоса", subtitle: "5 пресетов для голосовых сообщений, применяется перед отправкой."),
    PampGramPremiumFeature(systemImageName: "bolt.fill", color: UIColor(rgb: 0xff9500), title: "Ускорение передачи", subtitle: "Турбо-режим для загрузки и скачивания файлов."),
    PampGramPremiumFeature(systemImageName: "photo.on.rectangle.angled", color: UIColor(rgb: 0x8e44ec), title: "Сохранение историй", subtitle: "Скриншот и запись экрана без чёрного экрана, «Сохранить» даже для защищённых историй."),
    PampGramPremiumFeature(systemImageName: "timer", color: UIColor(rgb: 0x636366), title: "Показ временной медиа", subtitle: "Фото и видео с таймером — как обычные, без размытия и «одного просмотра»."),
    PampGramPremiumFeature(systemImageName: "pin.fill", color: UIColor(rgb: 0xff3b30), title: "Без лимитов", subtitle: "Закрепляй сколько угодно чатов и сними клиентские ограничения Premium."),
    PampGramPremiumFeature(systemImageName: "lock.fill", color: UIColor(rgb: 0x8e8e93), title: "Блокировка и геопозиция", subtitle: "PIN-код на выбранные чаты и фейковая точка для трансляции."),
]

private final class PampGramPremiumFeatureRow: UIView {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(feature: PampGramPremiumFeature) {
        super.init(frame: .zero)

        self.backgroundColor = UIColor(rgb: 0x18181f)
        self.layer.cornerRadius = 16.0

        self.iconContainer.backgroundColor = feature.color
        self.iconContainer.layer.cornerRadius = 11.0
        self.addSubview(self.iconContainer)

        self.iconView.image = UIImage(systemName: feature.systemImageName)?.withRenderingMode(.alwaysTemplate)
        self.iconView.tintColor = .white
        self.iconView.contentMode = .scaleAspectFit
        self.iconContainer.addSubview(self.iconView)

        self.titleLabel.text = feature.title
        self.titleLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.numberOfLines = 0
        self.addSubview(self.titleLabel)

        self.subtitleLabel.text = feature.subtitle
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.subtitleLabel.numberOfLines = 0
        self.addSubview(self.subtitleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let textWidth = width - 24.0 - 44.0 - 12.0 - 16.0
        let titleHeight = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let subtitleHeight = self.subtitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        return max(44.0 + 24.0, 16.0 + titleHeight + 4.0 + subtitleHeight + 16.0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let iconSide: CGFloat = 44.0
        self.iconContainer.frame = CGRect(x: 16.0, y: 16.0, width: iconSide, height: iconSide)
        let glyphSide: CGFloat = 22.0
        self.iconView.frame = CGRect(x: (iconSide - glyphSide) / 2.0, y: (iconSide - glyphSide) / 2.0, width: glyphSide, height: glyphSide)

        let textX = self.iconContainer.frame.maxX + 12.0
        let textWidth = self.bounds.width - textX - 16.0
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.titleLabel.frame = CGRect(x: textX, y: 16.0, width: textWidth, height: titleSize.height)
        let subtitleSize = self.subtitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.subtitleLabel.frame = CGRect(x: textX, y: self.titleLabel.frame.maxY + 4.0, width: textWidth, height: subtitleSize.height)
    }
}

private final class PampGramPremiumViewController: UIViewController {
    private let context: AccountContext

    private let scrollView = UIScrollView()
    private let closeButton = UIButton(type: .system)
    private let badgeLabel = UILabel()
    private let logoView = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private var featureRows: [PampGramPremiumFeatureRow] = []
    private let footerLabel = UILabel()
    private let ctaButton = UIButton(type: .system)

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(rgb: 0x0e0e14)

        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.alwaysBounceVertical = true
        self.view.addSubview(self.scrollView)

        self.closeButton.setImage(UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.7)
        self.closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.closeButton.layer.cornerRadius = 16.0
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)

        self.badgeLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
        self.badgeLabel.textColor = .white
        self.badgeLabel.textAlignment = .center
        self.badgeLabel.backgroundColor = UIColor(rgb: 0x8e44ec)
        self.badgeLabel.layer.cornerRadius = 10.0
        self.badgeLabel.layer.masksToBounds = true
        self.scrollView.addSubview(self.badgeLabel)

        self.logoView.image = pampGramSettingsIcon(size: 64.0)
        self.logoView.contentMode = .scaleAspectFit
        self.scrollView.addSubview(self.logoView)

        self.titleLabel.text = "PampGram Premium"
        self.titleLabel.font = UIFont.systemFont(ofSize: 24.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.scrollView.addSubview(self.titleLabel)

        self.statusLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
        self.statusLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.scrollView.addSubview(self.statusLabel)

        for feature in pampGramPremiumFeatures {
            let row = PampGramPremiumFeatureRow(feature: feature)
            self.scrollView.addSubview(row)
            self.featureRows.append(row)
        }

        self.footerLabel.text = "Работает через ключ активации — без покупок Apple ID и подписок в App Store. Ключ выдаёт команда PampGram."
        self.footerLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .regular)
        self.footerLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        self.footerLabel.textAlignment = .center
        self.footerLabel.numberOfLines = 0
        self.scrollView.addSubview(self.footerLabel)

        self.ctaButton.backgroundColor = .white
        self.ctaButton.setTitleColor(.black, for: .normal)
        self.ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.ctaButton.layer.cornerRadius = 14.0
        self.ctaButton.addTarget(self, action: #selector(self.ctaPressed), for: .touchUpInside)
        self.view.addSubview(self.ctaButton)

        self.reloadStatus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let topInset = self.view.safeAreaInsets.top
        let bottomInset = self.view.safeAreaInsets.bottom

        self.closeButton.frame = CGRect(x: 16.0, y: topInset + 8.0, width: 32.0, height: 32.0)

        let ctaHeight: CGFloat = 52.0
        let ctaBottomMargin: CGFloat = 12.0
        self.ctaButton.frame = CGRect(x: 20.0, y: self.view.bounds.height - bottomInset - ctaHeight - ctaBottomMargin, width: width - 40.0, height: ctaHeight)

        self.scrollView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: self.ctaButton.frame.minY)

        var y: CGFloat = topInset + 56.0

        self.badgeLabel.sizeToFit()
        let badgeWidth = self.badgeLabel.frame.width + 20.0
        self.badgeLabel.frame = CGRect(x: (width - badgeWidth) / 2.0, y: y, width: badgeWidth, height: 20.0)
        y = self.badgeLabel.frame.maxY + 16.0

        let logoSide: CGFloat = 64.0
        self.logoView.frame = CGRect(x: (width - logoSide) / 2.0, y: y, width: logoSide, height: logoSide)
        y = self.logoView.frame.maxY + 16.0

        let textWidth = min(320.0, width - 48.0)
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.titleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: titleSize.height)
        y = self.titleLabel.frame.maxY + 6.0

        let statusSize = self.statusLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.statusLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: statusSize.height)
        y = self.statusLabel.frame.maxY + 28.0

        let rowWidth = width - 32.0
        for row in self.featureRows {
            let rowHeight = row.height(forWidth: rowWidth)
            row.frame = CGRect(x: 16.0, y: y, width: rowWidth, height: rowHeight)
            y += rowHeight + 10.0
        }

        y += 10.0
        let footerSize = self.footerLabel.sizeThatFits(CGSize(width: width - 48.0, height: .greatestFiniteMagnitude))
        self.footerLabel.frame = CGRect(x: 24.0, y: y, width: width - 48.0, height: footerSize.height)
        y = self.footerLabel.frame.maxY + 24.0

        self.scrollView.contentSize = CGSize(width: width, height: y)
    }

    private func reloadStatus() {
        let _ = (PampGramSubscriptionAPI.fetchStatus(userId: self.context.account.peerId.id._internalGetInt64Value())
        |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let self else {
                return
            }
            self.apply(status: status)
        })
    }

    private func apply(status: PampGramSubscriptionStatus) {
        let isPro = status.tier == .pro
        self.badgeLabel.text = isPro ? "  PRO АКТИВЕН  " : "  STANDARD  "
        self.badgeLabel.backgroundColor = isPro ? UIColor(rgb: 0x34c759) : UIColor(rgb: 0x8e44ec)
        if isPro {
            if let expiresAt = status.expiresAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                self.statusLabel.text = "Premium активен до \(formatter.string(from: expiresAt))"
            } else {
                self.statusLabel.text = "Premium активен — без ограничения по сроку"
            }
            self.ctaButton.setTitle("Активировать ещё один ключ", for: .normal)
        } else {
            self.statusLabel.text = "Разблокируй Ghost, ускорение передачи и остальные функции ниже"
            self.ctaButton.setTitle("Активировать Premium", for: .normal)
        }
        self.view.setNeedsLayout()
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func ctaPressed() {
        pampGramPresentRedeemKeyFlow(context: self.context, presentController: { [weak self] controller in
            self?.present(controller, animated: true, completion: nil)
        }, presentTooltip: { [weak self] text in
            guard let self else {
                return
            }
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), animated: true, completion: nil)
        }, onActivated: { [weak self] status in
            self?.apply(status: status)
        })
    }
}

/// The Premium paywall — reached from the "Premium" button in the PampGram hub's top-right
/// corner, and from any section `pampGramGateTier` intercepts. Presented modally (like
/// `PampGramBannedScreen.swift`) rather than pushed, so it reads as a distinct "upsell" moment
/// rather than another settings page.
public func pampGramPresentPremiumScreen(context: AccountContext) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    presentingController.present(PampGramPremiumViewController(context: context), animated: true, completion: nil)
}

/// Opens `openReal` only when this account's subscription is already PRO; a STANDARD account
/// sees the Premium paywall instead. Used to gate whole hub sections (Ghost, Дополнительно) the
/// same way `pampGramGateSection` gates a banned one — separate mechanism, separate concern:
/// this is PampGram's own tier, not an admin ban.
public func pampGramGateTier(context: AccountContext, openReal: @escaping () -> Void) {
    let _ = (PampGramSubscriptionAPI.fetchStatus(userId: context.account.peerId.id._internalGetInt64Value())
    |> deliverOnMainQueue).start(next: { status in
        if status.tier == .pro {
            openReal()
        } else {
            pampGramPresentPremiumScreen(context: context)
        }
    })
}
